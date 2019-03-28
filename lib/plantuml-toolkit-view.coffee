{$, ScrollView} = require 'atom-space-pen-views'
{Disposable, CompositeDisposable, BufferedProcess} = require 'atom'
clipboard = null
path = null
fs = null
os = null
beautify_html = null

editorForId = (editorId) ->
  for editor in atom.workspace.getTextEditors()
    return editor if editor.id?.toString() is editorId.toString()
  null

settingsError = (message, setting, path) ->
  detail = "Verify '#{setting}' in settings."
  if path && path.match ///["']///
    detail += "\nSuggestion: Remove single/double quotes from the path string."
  options = {
    detail: detail,
    buttons: [{
        text: 'Open Package Settings',
        onDidClick: -> atom.workspace.open('atom://config/packages/plantuml-toolkit', searchAllPanes: true)
    }],
    dismissable: true
  }
  atom.notifications.addError "plantuml-toolkit: #{message}", options

module.exports =
class PlantumlPreviewView extends ScrollView
  @content: ->
    @div class: 'plantuml-toolkit padded pane-item', tabindex: -1, =>
      @div class: 'plantuml-control', outlet: 'control', =>
        @div =>
          @input id: 'zoomToFit', type: 'checkbox', outlet: 'zoomToFit'
          @label 'Zoom To Fit'
        @div =>
          @input id: 'useTempDir', type: 'checkbox', outlet: 'useTempDir'
          @label 'Use Temp Dir'
        @div =>
          @label 'Output'
          @select outlet: 'outputFormat', =>
            @option value: 'png', 'png'
            @option value: 'svg', 'svg'
          # selectedText is invisible -> see plantuml-toolkit.less
          @input id: 'selectedText', type: 'text', outlet: 'selectedText'
      @div class: 'plantuml-container', outlet: 'container'
  constructor: ({@editorId}) ->
    super
    @editor = editorForId @editorId
    @disposables = new CompositeDisposable
    @imageInfo = {scale: 1}

  destroy: ->
    @disposables.dispose()

  attached: ->
    if @editor?
      @useTempDir.attr('checked', atom.config.get('plantuml-toolkit.previewSettings.useTempDir'))
      @outputFormat.val atom.config.get('plantuml-toolkit.previewSettings.outputFormat')

      @zoomToFit.attr('checked', atom.config.get('plantuml-toolkit.previewSettings.zoomToFit'))
      checkHandler = (checked) =>
        @setZoomFit(checked)
      @on 'change', '#zoomToFit', ->
        checkHandler(@checked)

      saveHandler = =>
        @renderUml()
      @disposables.add @editor.getBuffer().onDidSave ->
        saveHandler()
      @outputFormat.change ->
        saveHandler()

      selectedInDiagramHandler = (value) =>
        @selectTextInEditor value
      @selectedText.change ->
        selectedInDiagramHandler(this.value)

      if atom.config.get 'plantuml-toolkit.previewSettings.bringFront'
        @disposables.add atom.workspace.onDidChangeActivePaneItem (item) =>
          if item is @editor
            pane = atom.workspace.paneForItem(this)
            if (typeof(pane) != 'undefined') && (pane != null)
              pane.activateItem this

      atom.commands.add @element,
        'plantuml-toolkit:preview-zoom-in': =>
          @imageInfo.scale = @imageInfo.scale * 1.1
          @scaleImages()
        'plantuml-toolkit:preview-zoom-out': =>
          @imageInfo.scale = @imageInfo.scale * 0.9
          @scaleImages()
        'plantuml-toolkit:preview-zoom-reset': =>
          @imageInfo.scale = 1
          @scaleImages()
        'plantuml-toolkit:preview-zoom-fit': =>
          @zoomToFit.prop 'checked', !@zoomToFit.is(':checked')
          @setZoomFit @zoomToFit.is(':checked')
        'plantuml-toolkit:copy-image': (event) =>
          filename = $(event.target).closest('.uml-image').attr('file')
          ext = path.extname(filename)
          switch ext
            when '.png'
              clipboard ?= require('electron').clipboard
              try
                clipboard.writeImage(filename)
              catch err
                atom.notifications.addError "plantuml-toolkit: Copy Failed", detail: "Error attempting to copy: #{filename}\nSee console for details.", dismissable: true
                console.log err
            when '.svg'
              try
                buffer = fs.readFileSync(filename, @editor.getEncoding())
                if atom.config.get 'plantuml-toolkit.previewSettings.beautifyXml'
                  beautify_html ?= require('js-beautify').html
                  buffer = beautify_html buffer
                atom.clipboard.write(buffer)
              catch err
                atom.notifications.addError "plantuml-toolkit: Copy Failed", detail: "Error attempting to copy: #{filename}\nSee console for details.", dismissable: true
                console.log err
            else
              atom.notifications.addError "plantuml-toolkit: Unsupported File Format", detail: "#{ext} is not currently supported by 'Copy Diagram'.", dismissable: true
        'plantuml-toolkit:open-file': (event) ->
          filename = $(event.target).closest('.open-file').attr('file')
          atom.workspace.open filename
        'plantuml-toolkit:copy-filename': (event) ->
          filename = $(event.target).closest('.copy-filename').attr('file')
          atom.clipboard.write filename

      @renderUml()

  getPath: ->
    if @editor?
      @editor.getPath()

  getURI: ->
    if @editor?
      "plantuml-toolkit://editor/#{@editor.id}"

  getTitle: ->
    if @editor?
      "#{@editor.getTitle()} Preview"

  onDidChangeTitle: ->
    new Disposable()

  onDidChangeModified: ->
    new Disposable()

  addImages: (imgFiles, time) ->
    @container.empty()
    displayFilenames = atom.config.get('plantuml-toolkit.previewSettings.displayFilename')
    for file in imgFiles
      if displayFilenames
        div = $('<div/>')
          .attr('class', 'filename open-file copy-filename')
          .attr('file', file)
          .text("#{file}")
        @container.append div
      imageInfo = @imageInfo
      zoomToFit = @zoomToFit.is(':checked')
      isSVG = path.extname(file) == '.svg'

      img = $('<img/>')
        .attr('src', "#{file}?time=#{time}")

      if isSVG
        img = $('<object/>')
          .attr('data', "#{file}?time=#{time}")
          .attr('type', "image/svg+xml")

        buffer = fs.readFileSync(file, 'UTF-8')
        if buffer.indexOf('<svg onclick') < 0 # only insert script if it was not inserted already
          buffer = buffer.replace "<svg ", '<svg onclick="if(window.parent.svgElementClicked) window.parent.svgElementClicked(event)" '
          fs.writeFileSync(file, buffer, 'UTF-8')

      img.attr('file', file)
        .load ->
          img = $(this)
          file = img.attr 'file'
          name = path.basename file, path.extname(file)
          if imageInfo.hasOwnProperty name
            info = imageInfo[name]
          else
            info = {}
          info.origWidth = img.width()
          info.origHeight = img.height()
          if isSVG
            svgAttr = img.context.contentDocument.childNodes[0].attributes
            info.origWidth = svgAttr.getNamedItem('width').nodeValue.replace("px", "")
            info.origHeight = svgAttr.getNamedItem('height').nodeValue.replace("px", "")
          imageInfo[name] = info

          img.attr('width', imageInfo.scale * info.origWidth)
          img.attr('height', imageInfo.scale * info.origHeight)
          img.attr('class', 'uml-image open-file copy-filename')

          if zoomToFit
            img.addClass('zoomToFit')

      @container.append img
    @container.append '
    <script type="text/javascript">
      function svgElementClicked(event) {
        if(event.srcElement.tagName == "text") {
          elm = document.getElementById("selectedText");
          elm.value = event.srcElement.innerHTML;
          elm.dispatchEvent(new Event("change"));
        }
      }
    </script>'
    @container.show

  scaleImages: ->
    for e in @container.find('.uml-image')
      img = $(e)
      file = img.attr 'file'
      name = path.basename file, path.extname(file)
      img.attr 'width', @imageInfo.scale * @imageInfo[name].origWidth
      img.attr 'height', @imageInfo.scale * @imageInfo[name].origHeight
    @zoomToFit.prop 'checked', false
    @setZoomFit @zoomToFit.is(':checked')

  removeImages: ->
    @container.empty()
    @container.append $('<div/>').attr('class', 'throbber')
    @container.show

  selectTextInEditor: (text) ->
    editor = @editor
    buffer = @editor.buffer
    searchText = text.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, '\\$&')
    buffer.findAll(searchText).then (ranges) ->
      if ranges.length > 0
        editor.clearSelections()
        for range in ranges
          editor.addSelectionForBufferRange(range)


  setZoomFit: (checked) ->
    if checked
      @container.find('.uml-image').addClass('zoomToFit')
    else
      @container.find('.uml-image').removeClass('zoomToFit')

  getFilenames: (directory, defaultName, defaultExtension, contents) ->
    path ?= require 'path'
    filenames = []
    defaultFilename = path.join(directory, defaultName)
    defaultCount = 0
    for uml in contents.split(///@end(?:uml|math|latex)///i)
      if uml.trim() == ''
        continue

      currentFilename = path.join(directory, defaultName)
      currentExtension = defaultExtension
      pageCount = 1

      filename = uml.match ///@start(?:uml|math|latex)([^\n]*)\n///i
      if filename?
        filename = filename[1].trim()
        if filename != ''
          if path.extname(filename)
            currentExtension = path.extname filename
          else
            currentExtension = defaultExtension
          currentFilename = path.join(directory, filename.replace(currentExtension, ''))

      if (currentFilename == defaultFilename)
        if defaultCount > 0
          countStr = defaultCount + ''
          countStr = '000'.substring(countStr.length) + countStr
          newfile = "#{currentFilename}_#{countStr}#{currentExtension}"
          filenames.push(newfile) unless newfile in filenames
        else
          newfile = currentFilename + currentExtension
          filenames.push(newfile) unless newfile in filenames
        defaultCount++
      else
        newfile = currentFilename + currentExtension
        filenames.push(newfile) unless newfile in filenames

      for line in uml.split('\n')
        if line.match ///^[\s]*(newpage)///i
          countStr = pageCount + ''
          countStr = '000'.substring(countStr.length) + countStr
          newfile = "#{currentFilename}_#{countStr}#{currentExtension}"
          filenames.push(newfile) unless newfile in filenames
          pageCount++

    filenames

  renderUml: ->
    path ?= require 'path'
    fs ?= require 'fs-plus'
    os ?= require 'os'

    filePath = @editor.getPath()
    basename = path.basename(filePath, path.extname(filePath))
    directory = path.dirname(filePath)
    format = @outputFormat.val()
    settingError = false

    if @useTempDir.is(':checked')
      directory = path.join os.tmpdir(), 'plantuml-toolkit'
      if !fs.existsSync directory
        fs.mkdirSync directory

    imgFiles = @getFilenames directory, basename, '.' + format, @editor.getText()

    upToDate = true
    fileTime = fs.statSync(filePath).mtime
    for image in imgFiles
      if fs.isFileSync(image)
        if fileTime > fs.statSync(image).mtime
          upToDate = false
          break
      else
        upToDate = false
        break
    if upToDate
      @removeImages()
      @addImages imgFiles, Date.now()
      return

    command = atom.config.get 'plantuml-toolkit.previewSettings.java'
    if (command != 'java') and (!fs.isFileSync command)
      settingsError "#{command} is not a file.", 'Java Executable', command
      settingError = true

    jarLocation = path.join(__dirname, '../vendor', 'plantuml.jar')

    if !fs.isFileSync jarLocation
      jarPathInConfig = atom.config.get('plantuml-toolkit.previewSettings.jarPlantuml')
      if !fs.isFileSync jarPathInConfig
        settingsError "Could not locate PlantUML's JAR. Please set 'PlantUML Jar Path' in configuration", 'PlantUML Jar', jarLocation
        settingError = true
      else
        jarLocation = jarPathInConfig

    dotLocation = atom.config.get('plantuml-toolkit.previewSettings.dotLocation')
    if dotLocation != ''
      if !fs.isFileSync dotLocation
        settingsError "#{dotLocation} is not a file.", 'Graphvis Dot Executable', dotLocation
        settingError = true

    if settingError
      @container.empty()
      @container.show
      return

    args = ['-Djava.awt.headless=true', '-Xmx1024m', '-DPLANTUML_LIMIT_SIZE=16800']
    javaAdditional = atom.config.get('plantuml-toolkit.previewSettings.javaAdditional')
    if javaAdditional != ''
      args.push javaAdditional

    args.push '-jar', jarLocation

    jarAdditional = atom.config.get('plantuml-toolkit.previewSettings.jarAdditional')
    if jarAdditional != ''
      args.push jarAdditional
    args.push '-charset', @editor.getEncoding()
    if format == 'svg'
      args.push '-tsvg'
    if dotLocation != ''
      args.push '-graphvizdot', dotLocation
    args.push '-output', directory, filePath

    outputlog = []
    errorlog = []

    exitHandler = (files) =>
      for file in files
        if fs.isFileSync file
          if atom.config.get('plantuml-toolkit.previewSettings.beautifyXml') and (format == 'svg')
            beautify_html ?= require('js-beautify').html
            buffer = fs.readFileSync(file, @editor.getEncoding())
            buffer = beautify_html buffer
            fs.writeFileSync(file, buffer, {encoding: @editor.getEncoding()})
        else
          console.log("File not found: #{file}")
      @addImages(files, Date.now())
      if errorlog.length > 0
        str = errorlog.join('')
        if str.match ///jarfile///i
          settingsError str, 'PlantUML Jar', jarLocation
        else
          console.log "plantuml-toolkit: stderr\n#{str}"
      if outputlog.length > 0
        str = outputlog.join('')
        atom.notifications.addInfo "plantuml-toolkit: stdout (logged to console)", detail: str, dismissable: true
        console.log "plantuml-toolkit: stdout\n#{str}"

    exit = (code) ->
      exitHandler imgFiles
    stdout = (output) ->
      outputlog.push output
    stderr = (output) ->
      errorlog.push output
    errorHandler = (object) ->
      object.handle()
      settingsError "#{command} not found.", 'Java Executable', command

    @removeImages()
    console.log("#{command} #{args.join ' '}")
    new BufferedProcess({command, args, stdout, stderr, exit}).onWillThrowError errorHandler
