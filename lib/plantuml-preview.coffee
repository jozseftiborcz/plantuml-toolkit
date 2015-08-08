fs = require 'fs-plus'
url = require 'url'
PlantumlPreviewView = null

uriForEditor = (editor) ->
  "plantuml-preview://editor/#{editor.id}"

isPlantumlPreviewView = (object) ->
  PlantumlPreviewView ?= require './plantuml-preview-view'
  object instanceof PlantumlPreviewView

removePreviewForEditor = (editor) ->
  uri = uriForEditor(editor)
  previewPane = atom.workspace.paneForURI(uri)
  if previewPane?
    previewPane.destroyItem(previewPane.itemForURI(uri))
    true
  else
    false

addPreviewForEditor = (editor) ->
  uri = uriForEditor(editor)
  previousActivePane = atom.workspace.getActivePane()
  if editor and fs.isFileSync(editor.getPath())
    options =
      searchAllPanes: true
      split: 'right'
    atom.workspace.open(uri, options).done (plantumlPreviewView) ->
      if isPlantumlPreviewView(plantumlPreviewView)
        previousActivePane.activate()
  else
    console.warn "Editor has not been saved to file."

toggle = ->
  if isPlantumlPreviewView(atom.workspace.getActivePaneItem())
    atom.workspace.destroyActivePaneItem()
    return

  editor = atom.workspace.getActiveTextEditor()
  return unless editor?

  addPreviewForEditor(editor) unless removePreviewForEditor(editor)

module.exports =
  config:
    java:
      type: 'string'
      default: 'java'
    jarLocation:
      type: 'string'
      default: 'plantuml.jar'
    zoomToFit:
      type: 'boolean'
      default: false

  activate: ->
    atom.commands.add 'atom-workspace', 'plantuml-preview:toggle', => toggle()
    @openerDisposable = atom.workspace.addOpener (uriToOpen) ->
      {protocol, host, pathname} = url.parse uriToOpen
      return unless protocol is 'plantuml-preview:'

      PlantumlPreviewView ?= require './plantuml-preview-view'
      new PlantumlPreviewView(editorId: pathname.substring(1))

  deactivate: ->
    @openerDisposable.dispose()
