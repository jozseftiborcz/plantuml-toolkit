{$} = require 'atom-space-pen-views'
{BufferedProcess} = require 'atom'
fs = null
path = null
url = require 'url'
beautify_html = null
os = null
PlantumlPreviewView = null
DEFAULT_ENCODING = 'UTF-8'
selectedFilePath = null
settingError = false
command = null
jarLocation = null
dotLocation = null

module.exports =
  config:
    languageSettings:
      title: 'Language'
      type: 'object'
      description: 'Options for PlantUML Language'
      collapsed: true
      properties:
        snippetsPath:
          title: 'Snippets Path'
          type: 'string'
          description: 'The path to the folder with your custom snippets for PlantUML diagrams'
          default: ''
          order: 0
    previewSettings:
      title: 'Preview'
      type: 'object'
      description: 'Options for PlantUML Preview'
      collapsed: true
      properties:
        outputFormat:
          title: 'Output Format'
          type: 'string'
          default: 'svg'
          enum: ['png', 'svg']
          order: 0
        java:
          title: 'Java Executable'
          description: 'Path to and including Java executable. If default, Java found on System Path will be used.'
          type: 'string'
          default: 'java'
          order: 1
        javaAdditional:
          title: 'Additional Java Arguments'
          description: 'Such as -DPLANTUML_LIMIT_SIZE=8192 or -Xmx1024m. -Djava.awt.headless=true arguement is included by default.'
          type: 'string'
          default: ''
          order: 2
        jarPlantuml:
          title: 'PlantUML Jar Path'
          description: 'Path to PlantUML\'s Jar. Should be set only if automatic configuration fails.'
          type: 'string'
          default: ''
          order: 3
        jarAdditional:
          title: 'Additional PlantUML Arguments'
          description: 'Arguments are added immediately after -jar. Arguments specified in settings may override.'
          type: 'string'
          default: ''
          order: 4
        dotLocation:
          title: 'Graphvis Dot Executable'
          description: "Path to and including Dot executable. If empty string, '-graphvizdot' argument will not be used."
          type: 'string'
          default: ''
          order: 5
        zoomToFit:
          type: 'boolean'
          default: true
          order: 6
        displayFilename:
          title: 'Display Filename Above UML Diagrams'
          type: 'boolean'
          default: true
          order: 7
        bringFront:
          title: 'Bring To Front'
          description: 'Bring preview to front when parent editor gains focus.'
          type: 'boolean'
          default: false
          order: 8
        useTempDir:
          title: 'Use Temp Directory'
          description: 'Output diagrams to {OS Temp Dir}/plantuml-bundle/'
          type: 'boolean'
          default: true
          order: 9
        beautifyXml:
          title: 'Beautify XML'
          description: 'Use js-beautify on XML when copying and generating SVG diagrams.'
          type: 'boolean'
          default: true
          order: 10

  initialize: (serializeState) ->
      atom.commands.add 'atom-workspace',
        'plantuml-bundle:togglePreview': -> toggle()
        'plantuml-bundle:generatePNG': -> generate 'png'
        'plantuml-bundle:generateSVG': -> generate 'svg'
        'plantuml-bundle:generateTXT': -> generate 'utxt'

      os ?= require 'os'
      fs ?= require 'fs-plus'
      path ?= require 'path'

      command = atom.config.get 'plantuml-bundle.previewSettings.java'
      if (command != 'java') and (!fs.isFileSync command)
        notifyError 'Java Executable', "#{command} is not a file."
        settingError = true

      jarLocation = path.join(__dirname, '../vendor', 'plantuml.jar')

      if !fs.isFileSync jarLocation
        jarPathInConfig = atom.config.get('plantuml-bundle.previewSettings.jarPlantuml')
        if !fs.isFileSync jarPathInConfig
            settingsError 'PlantUML Jar', "Could not locate PlantUML's JAR [path=#{jarPathInConfig}]. Please set 'PlantUML Jar Path' in configuration"
            settingError = true
        else
            jarLocation = jarPathInConfig

      dotLocation = atom.config.get('plantuml-bundle.previewSettings.dotLocation')
      if dotLocation != ''
        if !fs.isFileSync dotLocation
            settingsError 'Graphvis Dot Executable', "#{dotLocation} is not a file."
            settingError = true

      snippetsPath = atom.config.get('plantuml-bundle.languageSettings.snippetsPath')
      if snippetsPath != ''
        fs.isDirectory snippetsPath, (isDirectory) ->
          if !isDirectory
            settingsError 'Custom Snippets', "The path [#{snippetsPath}] set in plantuml-bundle configuration is not a valid directory"
            settingError = true
          else
            snippetsPackage = atom.packages.getLoadedPackage('snippets')

            snippetsPackage.grammarsPromise.then (response) ->
              loadCustomSnippets snippetsPackage.mainModule, snippetsPath

  activate: ->
      @openerDisposable = atom.workspace.addOpener (uriToOpen) ->
        {protocol, host, pathname} = url.parse uriToOpen
        return unless protocol is 'plantuml-bundle:'

        PlantumlPreviewView ?= require './plantuml-bundle-view'
        new PlantumlPreviewView(editorId: pathname.substring(1))

  deactivate: ->
      @openerDisposable.dispose()

loadCustomSnippets = (snippetsModule, customSnippetsPath) ->
  snippetsModule.loadSnippetsDirectory customSnippetsPath, (error, loadedSnippets) ->
    if error
      settingsError 'Custom Snippets', "Failed to retrieve custom snippets at [#{customSnippetsPath}]: #{error}"
      settingError = true
    else
      packageSnippets = snippetsModule.snippetsByPackage.get('plantuml-bundle')
      selectedPackageFilePath = Object.keys(packageSnippets)[0]
      atom.config.transact =>
        for filepath, snippetsBySelector of loadedSnippets
          snippetsModule.add(filepath, snippetsBySelector)
          Object.assign(
            packageSnippets[selectedPackageFilePath]['.source.plantuml'],
            snippetsBySelector['.source.plantuml'])

settingsError = (title, message) ->
  options = {
    detail: message
    dismissable: true
  }
  atom.notifications.addError "plantuml-bundle: #{title}", options

uriForEditor = (editor) ->
  "plantuml-bundle://editor/#{editor.id}"

isPlantumlPreviewView = (object) ->
  PlantumlPreviewView ?= require './plantuml-bundle-view'
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
  fs ?= require 'fs-plus'
  uri = uriForEditor(editor)
  previousActivePane = atom.workspace.getActivePane()
  if editor and fs.isFileSync(editor.getPath())
    options =
      searchAllPanes: true
      split: 'right'
    atom.workspace.open(uri, options).then (plantumlPreviewView) ->
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

notifyError = (title, message) ->
  options = {
    detail: message,
    dismissable: true
  }
  atom.notifications.addError "plantuml-bundle: #{title}", options

generate = (imageType) ->
  if settingError
    notifyError "There's an error with your settings. Please, fix them before continuing"
    return

  fs ?= require 'fs-plus'
  path ?= require 'path'

  selectedItemPath = $('.tree-view .selected span').data('path')
  fs.lstat(selectedItemPath, (err, stats) ->
    if(err)
      notifyError('Unexpected error', err)
      return

    dirRequest = null
    sourceRequest = null
    isDir = false
    if stats.isDirectory()
      dirRequest = selectedItemPath
      sourceRequest = dirRequest + '/**.puml'
      isDir = true
    else if stats.isFile()
      dirRequest = selectedItemPath.substr(0, selectedItemPath.lastIndexOf(path.sep))
      sourceRequest = selectedItemPath

    destinationDir = dirRequest + '/images'

    args = ['-Djava.awt.headless=true', '-Xmx1024m', '-DPLANTUML_LIMIT_SIZE=16800']
    javaAdditional = atom.config.get('plantuml-bundle.previewSettings.javaAdditional')
    if javaAdditional != ''
      args.push javaAdditional

    args.push '-jar', jarLocation

    jarAdditional = atom.config.get('plantuml-bundle.previewSettings.jarAdditional')
    if jarAdditional != ''
      args.push jarAdditional
    args.push '-failfast2'
    args.push '-charset', DEFAULT_ENCODING
    args.push '-t' + imageType
    if dotLocation != ''
      args.push '-graphvizdot', dotLocation
    args.push '-output', destinationDir, sourceRequest

    outputlog = []
    errorlog = []

    exitHandler = (files) =>
      for file in files
        if fs.isFileSync file
          if atom.config.get('plantuml-bundle.previewSettings.beautifyXml') and (format == 'svg')
            beautify_html ?= require('js-beautify').html
            buffer = fs.readFileSync(file, DEFAULT_ENCODING)
            buffer = beautify_html buffer
            fs.writeFileSync(file, buffer, {encoding: DEFAULT_ENCODING})
        else
          console.log("File not found: #{file}")

      if errorlog.length > 0
        str = errorlog.join('')

      if str.match ///jarfile///i
        notifyError 'PlantUML Jar', str + " [#{jarLocation}]"
      else
        console.log "plantuml-bundle: stderr\n#{str}"
      if outputlog.length > 0
        str = outputlog.join('')

      atom.notifications.addInfo "plantuml-bundle: stdout (logged to console)", detail: str, dismissable: true
      console.log "plantuml-bundle: stdout\n#{str}"

    exit = (code) ->
      #exitHandler imgFiles
      console.log code
      if code == 100
        if isDir
          atom.notifications.addWarning "plantuml-bundle: No diagrams", detail: "No diagrams found in folder #{dirRequest}", dismissable: true
        else
          atom.notifications.addWarning "plantuml-bundle: Not a diagram", detail: "#{selectedItemPath} is not a supported diagram", dismissable: true
      else if code == 200
        if isDir
          notifyError 'Syntax error', "There are syntax errors in one or more diagrams: #{dirRequest}"
        else
          notifyError 'Syntax error', "There are syntax errors in #{selectedItemPath}"
      else if code == 0
        if isDir
          atom.notifications.addSuccess "plantuml-bundle: Success", detail: "The diagrams were successfully generated", dismissable: true
        else
          atom.notifications.addSuccess "plantuml-bundle: Success", detail: "The diagram was successfully generated", dismissable: true
      else
        notifyError 'Unexpected error', "An unexpected error occurred."
    stdout = (output) ->
      outputlog.push output
    stderr = (output) ->
      errorlog.push output
    errorHandler = (object) ->
      object.handle()
      notifyError 'Java Executable', "#{command} not found."

    console.log("#{command} #{args.join ' '}")
    new BufferedProcess({command, args, stdout, stderr, exit}).onWillThrowError errorHandler

  )
