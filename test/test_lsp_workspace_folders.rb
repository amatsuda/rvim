# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

# Workspace folders + server-to-client request acks. Tests:
#   - Client seeds folders from root_uri, sends them in initialize,
#     runtime add/remove dispatches didChangeWorkspaceFolders
#   - Server-to-client requests (registerCapability,
#     unregisterCapability, workspaceFolders, configuration) get
#     proper responses so the server doesn't hang
#   - Manager aggregates folders across clients and fans out runtime
#     changes
#   - Editor commands list / add / remove folders

class TestLspWorkspaceFoldersClient < Test::Unit::TestCase
  def make_client(root_uri: 'file:///tmp/proj', workspace_folders: nil)
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'],
                                    root_uri: root_uri, workspace_folders: workspace_folders)
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_default_workspace_folders_from_root_uri
    c = make_client(root_uri: 'file:///work/proj')
    assert_equal [{ uri: 'file:///work/proj', name: 'proj' }], c.workspace_folders
  end

  def test_explicit_workspace_folders_overrides_default
    explicit = [{ uri: 'file:///a', name: 'a' }, { uri: 'file:///b', name: 'b' }]
    c = make_client(workspace_folders: explicit)
    assert_equal explicit, c.workspace_folders
  end

  def test_initialize_sends_workspaceFolders_param
    c = make_client
    sent = nil
    c.define_singleton_method(:send_message) { |body| sent = body }
    c.instance_variable_set(:@status, :stopped)
    c.send(:send_initialize)
    assert_equal c.workspace_folders, sent.dig(:params, :workspaceFolders)
  end

  def test_add_workspace_folder_notifies_server_and_updates_state
    c = make_client
    sent = nil
    c.define_singleton_method(:send_message) { |b| sent = b }
    assert c.add_workspace_folder('file:///work/other', 'other')
    assert_equal 'workspace/didChangeWorkspaceFolders', sent[:method]
    assert_equal({ uri: 'file:///work/other', name: 'other' },
                 sent.dig(:params, :event, :added).first)
    assert_empty sent.dig(:params, :event, :removed)
    assert(c.workspace_folders.any? { |f| f[:uri] == 'file:///work/other' })
  end

  def test_add_workspace_folder_dedupes_existing
    c = make_client
    c.define_singleton_method(:send_message) { |_| }
    refute c.add_workspace_folder('file:///tmp/proj') # already seeded
  end

  def test_remove_workspace_folder_notifies_and_drops
    c = make_client(workspace_folders: [{ uri: 'file:///a', name: 'a' }])
    sent = nil
    c.define_singleton_method(:send_message) { |b| sent = b }
    assert c.remove_workspace_folder('file:///a')
    assert_equal 'workspace/didChangeWorkspaceFolders', sent[:method]
    assert_equal({ uri: 'file:///a', name: 'a' },
                 sent.dig(:params, :event, :removed).first)
    assert_empty c.workspace_folders
  end

  def test_remove_returns_false_when_not_tracked
    c = make_client
    c.define_singleton_method(:send_message) { |_| }
    refute c.remove_workspace_folder('file:///nope')
  end
end

class TestLspClientRequestAcks < Test::Unit::TestCase
  def make_client
    client = Rvim::Lsp::Client.new(name: 'fake', command: ['true'], root_uri: 'file:///tmp/x')
    client.instance_variable_set(:@stdin, StringIO.new)
    client.instance_variable_set(:@status, :running)
    client
  end

  def test_registerCapability_request_gets_empty_ack
    c = make_client
    sent = nil
    c.define_singleton_method(:send_message) { |b| sent = b }
    msg = { id: 7, method: 'client/registerCapability',
            params: { registrations: [{ id: 'r1', method: 'workspace/didChangeWatchedFiles' }] } }
    c.send(:handle_notification_or_request, msg)
    assert_equal 7, sent[:id]
    assert_nil sent[:result]
    assert_equal 'workspace/didChangeWatchedFiles',
                 c.instance_variable_get(:@registered_capabilities)['r1']
  end

  def test_unregisterCapability_clears_and_acks
    c = make_client
    c.instance_variable_get(:@registered_capabilities)['r1'] = 'workspace/didChangeWatchedFiles'
    sent = nil
    c.define_singleton_method(:send_message) { |b| sent = b }
    msg = { id: 8, method: 'client/unregisterCapability',
            params: { unregisterations: [{ id: 'r1', method: 'workspace/didChangeWatchedFiles' }] } }
    c.send(:handle_notification_or_request, msg)
    assert_equal 8, sent[:id]
    assert_empty c.instance_variable_get(:@registered_capabilities)
  end

  def test_workspaceFolders_request_returns_current_folders
    c = make_client
    sent = nil
    c.define_singleton_method(:send_message) { |b| sent = b }
    msg = { id: 9, method: 'workspace/workspaceFolders' }
    c.send(:handle_notification_or_request, msg)
    assert_equal 9, sent[:id]
    assert_equal c.workspace_folders, sent[:result]
  end

  def test_configuration_request_returns_nils_for_each_section
    c = make_client
    sent = nil
    c.define_singleton_method(:send_message) { |b| sent = b }
    msg = { id: 10, method: 'workspace/configuration',
            params: { items: [{ section: 'ruby' }, { section: 'rvim' }] } }
    c.send(:handle_notification_or_request, msg)
    assert_equal [nil, nil], sent[:result]
  end
end

class TestLspManagerWorkspaceFolders < Test::Unit::TestCase
  class FakeClient
    attr_accessor :status, :workspace_folders, :added, :removed
    def initialize(folders, status: :running)
      @status = status
      @workspace_folders = folders
      @added = []
      @removed = []
    end
    def add_workspace_folder(uri, name = nil)
      return false if @workspace_folders.any? { |f| f[:uri] == uri }
      @added << uri
      @workspace_folders << { uri: uri, name: name }
      true
    end
    def remove_workspace_folder(uri)
      found = @workspace_folders.find { |f| f[:uri] == uri }
      return false unless found
      @removed << uri
      @workspace_folders.delete(found)
      true
    end
  end

  def setup
    @editor = Rvim::Editor.new(Reline.core.config)
    @manager = Rvim::Lsp::Manager.new(@editor)
  end

  def test_workspace_folders_dedupes_across_clients
    a = FakeClient.new([{ uri: 'file:///x', name: 'x' }])
    b = FakeClient.new([{ uri: 'file:///x', name: 'x' }, { uri: 'file:///y', name: 'y' }])
    @manager.instance_variable_set(:@clients, ruby: a, py: b)
    assert_equal %w[file:///x file:///y], @manager.workspace_folders.map { |f| f[:uri] }
  end

  def test_add_workspace_folder_fans_out_returns_running_client_count
    a = FakeClient.new([])
    b = FakeClient.new([], status: :starting)
    @manager.instance_variable_set(:@clients, ruby: a, py: b)
    n = @manager.add_workspace_folder('file:///z')
    assert_equal 1, n, 'only running clients get the change'
    assert_equal ['file:///z'], a.added
    assert_empty b.added
  end

  def test_remove_workspace_folder_only_counts_clients_that_had_it
    a = FakeClient.new([{ uri: 'file:///z', name: 'z' }])
    b = FakeClient.new([])
    @manager.instance_variable_set(:@clients, ruby: a, py: b)
    assert_equal 1, @manager.remove_workspace_folder('file:///z')
  end
end
