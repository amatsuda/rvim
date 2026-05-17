# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

class TestLspHoverClient < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_handle_response_stores_hover_result
    client = make_client
    client.instance_variable_get(:@pending)[1] = ['textDocument/hover', 'file:///x']
    msg = { id: 1, result: { contents: { kind: 'markdown', value: '# Title' } } }
    client.send(:handle_response, msg)
    assert_equal 'markdown', client.last_hover_result.dig(:contents, :kind)
  end

  def test_hover_clears_previous_result
    client = make_client
    client.define_singleton_method(:send_message) { |_| nil }
    client.last_hover_result = { contents: 'old' }
    client.hover('file:///x', 0, 0)
    assert_nil client.last_hover_result
  end
end

class TestLspHoverManager < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :last_hover_result, :hover_calls

    def initialize
      @status = :running
      @hover_calls = []
      @last_hover_result = nil
    end

    def hover(uri, line, character)
      @hover_calls << { uri: uri, line: line, character: character }
    end

    def diagnostics; {}; end
    def flush_changes(_buf); false; end
    def pending_for?(_); false; end
    def pump; end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @manager = Rvim::Lsp::Manager.new(@editor)
    @manager.define_singleton_method(:filetype_for) { |_| :ruby }
    @manager.define_singleton_method(:buffer_uri) { |_| 'file:///x.rb' }
    @client = FakeClient.new
    @manager.instance_variable_set(:@clients, { ruby: @client })
  end

  def make_buffer
    Rvim::Buffer.new(1, '/tmp/x.rb').tap { |b| b.lines = ['x = 1'] }
  end

  def test_request_hover_sends_cursor_position
    @editor.instance_variable_set(:@line_index, 3)
    @editor.instance_variable_set(:@byte_pointer, 5)
    assert @manager.request_hover(make_buffer)
    call = @client.hover_calls.first
    assert_equal 3, call[:line]
    assert_equal 5, call[:character]
  end

  def test_request_hover_returns_false_without_client
    @manager.instance_variable_set(:@clients, {})
    refute @manager.request_hover(make_buffer)
  end

  def test_last_hover_result_reads_from_client
    @client.last_hover_result = { contents: { value: 'hello' } }
    assert_equal 'hello', @manager.last_hover_result.dig(:contents, :value)
  end
end

class TestEditorParseHoverContents < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
  end

  def parse(result)
    @editor.send(:parse_hover_contents, result)
  end

  def test_nil_result
    assert_equal [], parse(nil)
  end

  def test_markup_content
    # Markdown rendering strips the heading prefix; the title text survives.
    out = parse({ contents: { kind: 'markdown', value: "# Title\nbody line" } })
    assert_equal ['Title', 'body line'], out
  end

  def test_markup_content_plaintext_kind_is_not_rendered
    # When the server explicitly says `kind: 'plaintext'`, leave the text alone.
    out = parse({ contents: { kind: 'plaintext', value: "# raw asterisks **stay**" } })
    assert_equal ['# raw asterisks **stay**'], out
  end

  def test_legacy_marked_string_object
    out = parse({ contents: { language: 'ruby', value: "def foo\n  1\nend" } })
    assert_equal ['def foo', '  1', 'end'], out
  end

  def test_legacy_marked_string_plain
    out = parse({ contents: 'just a string' })
    assert_equal ['just a string'], out
  end

  def test_marked_string_array
    out = parse({ contents: ['plain', { language: 'ruby', value: "def foo\nend" }] })
    assert_equal ['plain', 'def foo', 'end'], out
  end

  def test_empty_value_returns_empty
    # An empty value string is "no hover info" — caller surfaces a status
    # message instead of opening an empty popup.
    assert_equal [], parse({ contents: { kind: 'plaintext', value: '' } })
  end

  def test_no_contents_field
    assert_equal [], parse({})
  end
end

class TestHoverPopupKeyConsumption < Test::Unit::TestCase
  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    # 30-line hover content so the popup needs scrolling.
    contents = (1..30).map { |i| "line #{i}" }
    @editor.instance_variable_set(:@hover_popup,
      Rvim::CompletionPopup.new(contents: contents, max_height: 8, max_width: 80))
    @popup = @editor.hover_popup
  end

  def key(ch); Reline::Key.new(ch, ch, false); end

  def test_ctrl_e_scrolls_down_one_line
    @editor.send(:consume_hover_popup_key, key(0x05))
    assert_equal 1, @popup.pointer
    refute_nil @editor.hover_popup
  end

  def test_ctrl_y_scrolls_up_one_line
    @popup.pointer = 5
    @editor.send(:consume_hover_popup_key, key(0x19))
    assert_equal 4, @popup.pointer
  end

  def test_ctrl_d_scrolls_half_page
    @editor.send(:consume_hover_popup_key, key(0x04))
    # visible_height=8, half=4
    assert_equal 4, @popup.pointer
  end

  def test_ctrl_u_scrolls_half_page_up
    @popup.pointer = 10
    @editor.send(:consume_hover_popup_key, key(0x15))
    assert_equal 6, @popup.pointer
  end

  def test_ctrl_f_scrolls_full_page_down
    @editor.send(:consume_hover_popup_key, key(0x06))
    assert_equal 8, @popup.pointer
  end

  def test_ctrl_b_scrolls_full_page_up
    @popup.pointer = 16
    @editor.send(:consume_hover_popup_key, key(0x02))
    assert_equal 8, @popup.pointer
  end

  def test_q_dismisses_popup
    @editor.send(:consume_hover_popup_key, key('q'.ord))
    assert_nil @editor.hover_popup
  end

  def test_esc_dismisses_popup
    @editor.send(:consume_hover_popup_key, key(0x1b))
    assert_nil @editor.hover_popup
  end

  def test_letter_is_passthrough
    refute @editor.send(:consume_hover_popup_key, key('j'.ord))
    refute_nil @editor.hover_popup, 'popup stays (caller will dismiss on passthrough)'
  end

  def test_scroll_clamps_at_bottom
    @popup.pointer = @popup.size - 1
    @editor.send(:consume_hover_popup_key, key(0x05))
    assert_equal @popup.size - 1, @popup.pointer
  end

  def test_scroll_clamps_at_top
    @popup.pointer = 0
    @editor.send(:consume_hover_popup_key, key(0x19))
    assert_equal 0, @popup.pointer
  end
end

class TestEditorRenderMarkdownForPopup < Test::Unit::TestCase
  def render(text)
    editor = Rvim::Editor.new(Reline.core.config)
    editor.send(:render_markdown_for_popup, text)
  end

  def test_strips_bold_markers
    assert_equal ['Definitions: link.rbs'], render('**Definitions**: link.rbs')
  end

  def test_strips_italic_markers
    assert_equal ['Note: emphasized'], render('Note: *emphasized*')
    assert_equal ['Note: emphasized'], render('Note: _emphasized_')
  end

  def test_does_not_collapse_bold_when_surrounded_by_word_chars
    # `foo*bar*baz` is NOT italic in markdown (no surrounding whitespace);
    # we err on the side of stripping. Verifies the regex doesn't blow up.
    assert_equal ['foobarbaz'], render('foo*bar*baz')
  end

  def test_strips_inline_code_backticks
    assert_equal ['Calls method foo on self.'], render('Calls method `foo` on self.')
  end

  def test_strips_link_wrappers_keeping_text
    assert_equal ['See String for details.'],
                 render('See [String](https://docs.example.com/String) for details.')
  end

  def test_strips_heading_prefixes
    assert_equal ['Title', 'Subtitle'], render("# Title\n## Subtitle")
  end

  def test_drops_fenced_code_block_delimiters_keeping_content
    src = <<~MD
      Example:
      ```ruby
      def foo
        1
      end
      ```
      after
    MD
    out = render(src)
    assert_equal ['Example:', 'def foo', '  1', 'end', 'after'], out
  end

  def test_inline_markers_inside_fenced_code_are_left_alone
    src = "```ruby\n**not_bold** and `not_code`\n```"
    assert_equal ['**not_bold** and `not_code`'], render(src)
  end

  def test_strips_html_comments_even_across_multiple_lines
    # The 3-line comment is removed in one shot; the surrounding
    # newlines collapse down to a single blank separator.
    src = "before\n<!--\n  rdoc note\n-->\nafter"
    assert_equal ['before', '', 'after'], render(src)
  end

  def test_strips_bare_html_tags
    assert_equal ['hello world'], render('<span>hello</span> <em>world</em>')
  end

  def test_collapses_runs_of_blank_lines
    src = "a\n\n\n\nb"
    assert_equal ['a', '', 'b'], render(src)
  end

  def test_trims_leading_and_trailing_blanks
    src = "\n\n\nbody\n\n\n"
    assert_equal ['body'], render(src)
  end
end

class TestEditorLspShowHover < Test::Unit::TestCase
  class FakeLsp
    attr_accessor :request_hover_returns, :result

    def initialize
      @request_hover_returns = true
      @result = nil
    end

    def request_hover(_buffer)
      @request_hover_returns
    end

    def last_hover_result
      @result
    end

    def flush_changes(_buf); false; end
    def pending_for?(_); false; end
    def pump; end
    def diagnostic_signs(_); {}; end
    def diagnostic_ranges(_); {}; end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @editor.settings.set(:lsp_enabled, true)
    @lsp = FakeLsp.new
    @editor.instance_variable_set(:@lsp, @lsp)

    @buf = Rvim::Buffer.new(1, '/tmp/x.rb')
    @buf.lines = ['x = 1']
    @editor.instance_variable_set(:@buffer_of_lines, @buf.lines)
    @editor.instance_variable_set(:@current_buffer, @buf)
    @editor.instance_variable_set(:@line_index, 0)
    @editor.instance_variable_set(:@byte_pointer, 0)
  end

  def test_returns_false_when_lsp_disabled
    @editor.settings.set(:lsp_enabled, false)
    refute @editor.lsp_show_hover
    assert_nil @editor.hover_popup
  end

  def test_returns_false_when_no_client
    @lsp.request_hover_returns = false
    refute @editor.lsp_show_hover
    assert_nil @editor.hover_popup
  end

  def test_returns_true_with_status_when_no_info
    @lsp.result = { contents: nil }
    assert @editor.lsp_show_hover
    assert_match(/no hover info/, @editor.status_message.to_s)
    assert_nil @editor.hover_popup
  end

  def test_builds_popup_when_result_has_content
    @lsp.result = { contents: { kind: 'markdown', value: "# foo\nbar" } }
    assert @editor.lsp_show_hover
    refute_nil @editor.hover_popup
    # Markdown is rendered for the popup — the `# ` heading prefix is stripped.
    assert_equal ['foo', 'bar'], @editor.hover_popup.contents
  end

  def test_update_dismisses_existing_popup
    @editor.config.editing_mode = :vi_command
    @editor.instance_variable_set(:@hover_popup,
      Rvim::CompletionPopup.new(contents: ['x']))
    refute_nil @editor.hover_popup
    sym = @editor.send(:synthesize_key, 'j').method_symbol
    @editor.update(Reline::Key.new('j', sym, false))
    assert_nil @editor.hover_popup
  end
end
