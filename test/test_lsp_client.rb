# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'
require 'json'

class TestLspClient < Test::Unit::TestCase
  # Builds a Client wired to a pair of pipes so we can drive both sides
  # in-process without spawning a subprocess. The client stays in :stopped
  # until #start is called; we manually plumb the IO streams via instance
  # variables to skip the popen3 step.
  def make_fake_client(on_diagnostic: nil)
    client = Rvim::Lsp::Client.new(
      name: 'fake', command: ['true'], root_uri: 'file:///tmp',
      on_diagnostic: on_diagnostic,
    )
    server_in_r, server_in_w = IO.pipe   # client writes, server reads
    server_out_r, server_out_w = IO.pipe # server writes, client reads
    [server_in_r, server_in_w, server_out_r, server_out_w].each(&:binmode)
    client.instance_variable_set(:@stdin, server_in_w)
    client.instance_variable_set(:@stdout, server_out_r)
    client.instance_variable_set(:@status, :starting)
    reader = Thread.new { client.send(:read_loop) }
    client.instance_variable_set(:@reader_thread, reader)
    [client, server_in_r, server_out_w]
  end

  def drain_inbox(client, timeout: 1.0)
    deadline = Time.now + timeout
    loop do
      client.pump
      break if Time.now > deadline
      break if client.instance_variable_get(:@inbox).empty? &&
               client.status != :starting

      sleep 0.01
    end
  end

  def read_message(io)
    headers = {}
    while (line = io.gets)
      line = line.chomp("\r\n").chomp("\n")
      break if line.empty?

      k, v = line.split(': ', 2)
      headers[k] = v if k && v
    end
    body = io.read(headers['Content-Length'].to_i)
    JSON.parse(body, symbolize_names: true)
  end

  def write_message(io, body)
    json = JSON.generate(body)
    io.write("Content-Length: #{json.bytesize}\r\n\r\n#{json}")
    io.flush
  end

  def test_initialize_request_is_well_formed
    client, server_in_r, _server_out_w = make_fake_client
    client.send(:send_initialize)
    msg = read_message(server_in_r)
    assert_equal '2.0', msg[:jsonrpc]
    assert_equal 'initialize', msg[:method]
    assert_equal 'file:///tmp', msg.dig(:params, :rootUri)
    assert_equal 'rvim', msg.dig(:params, :clientInfo, :name)
  end

  def test_did_open_notification_format
    client, server_in_r, = make_fake_client
    client.did_open('file:///x.rb', 'ruby', 1, "puts 1\n")
    msg = read_message(server_in_r)
    assert_equal 'textDocument/didOpen', msg[:method]
    assert_equal 'file:///x.rb', msg.dig(:params, :textDocument, :uri)
    assert_equal "puts 1\n", msg.dig(:params, :textDocument, :text)
  end

  def test_publish_diagnostics_calls_callback
    received = []
    client, _server_in_r, server_out_w = make_fake_client(on_diagnostic: ->(uri, diags) { received << [uri, diags] })
    write_message(server_out_w, jsonrpc: '2.0', method: 'textDocument/publishDiagnostics',
                                params: { uri: 'file:///x.rb',
                                          diagnostics: [{ range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
                                                          message: 'oops', severity: 1 }] })
    drain_inbox(client)
    assert_equal 1, received.size
    assert_equal 'file:///x.rb', received.first[0]
  end

  def test_diagnostics_stored_per_uri
    client, _server_in_r, server_out_w = make_fake_client
    write_message(server_out_w, jsonrpc: '2.0', method: 'textDocument/publishDiagnostics',
                                params: { uri: 'file:///x.rb',
                                          diagnostics: [{ message: 'm1', severity: 2 }] })
    drain_inbox(client)
    assert_equal 1, client.diagnostics['file:///x.rb'].size
  end

  def test_initialize_response_marks_client_running
    client, _server_in_r, server_out_w = make_fake_client
    client.send(:send_initialize)
    write_message(server_out_w, jsonrpc: '2.0', id: 1, result: { capabilities: { hoverProvider: true } })
    drain_inbox(client)
    assert_equal :running, client.status
    assert_equal true, client.capabilities[:hoverProvider]
  end
end

class TestLspClientWithRealRubyLsp < Test::Unit::TestCase
  def setup
    @ruby_lsp = `which ruby-lsp 2>/dev/null`.chomp
    omit 'ruby-lsp not on PATH' if @ruby_lsp.empty?
    omit 'set RVIM_TEST_REAL_LSP=1 to run (slow; spawns ruby-lsp)' unless ENV['RVIM_TEST_REAL_LSP']
  end

  def test_initialize_handshake_with_ruby_lsp
    Dir.mktmpdir('rvim-lsp') do |dir|
      file = File.join(dir, 'sample.rb')
      File.write(file, "x = 1\nputs x\n")

      client = Rvim::Lsp::Client.new(
        name: 'ruby-lsp', command: [@ruby_lsp], root_uri: "file://#{dir}", cwd: dir,
      )
      client.start
      deadline = Time.now + 60 # ruby-lsp boots a composed bundle on first run
      until client.tap(&:pump).status == :running || Time.now > deadline
        sleep 0.1
      end
      assert_equal :running, client.status, 'ruby-lsp did not finish initialize within 60s'
      refute_nil client.capabilities
      client.stop
    end
  end
end
