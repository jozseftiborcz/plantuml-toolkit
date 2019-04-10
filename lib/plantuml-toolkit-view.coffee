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
          @label 'Zoom To Fit', for: 'zoomToFit'
      @div class: 'plantuml-container', outlet: 'container'

  constructor: ({@editorId, @toolkitController}) ->
    super
    @editor = editorForId @editorId
    @disposables = new CompositeDisposable
    @imageInfo = {scale: 1}
    @toolkitController.addToPreviewsList(this)

  destroy: ->
    @toolkitController.removeFromPreviewsList(this)
    @disposables.dispose()

  attached: ->
    if @editor?
      @zoomToFit.attr('checked', atom.config.get('plantuml-toolkit.previewSettings.zoomToFit'))
      checkHandler = (checked) =>
        @setZoomFit(checked)
      @on 'change', '#zoomToFit', ->
        checkHandler(@checked)

      saveHandler = =>
        previousScrollTop = this.scrollTop()
        previousScrollLeft = this.scrollLeft()
        @renderUml({scrollTo: [previousScrollTop, previousScrollLeft]})

      @disposables.add @editor.getBuffer().onDidSave ->
        saveHandler()

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

      @disposables.add atom.views.getView(@editor).onDidChangeScrollTop (editorScrollTop) =>
        view = this
        editorVerticalScrollSize = @editor.component.getScrollBottom() - @editor.component.getScrollTop() + 100
        viewVerticalScrollSize = view.scrollBottom() - view.scrollTop()

        scrollTopEquivalence = @editor.component.getScrollTop() / (@editor.component.getScrollHeight() - editorVerticalScrollSize)
        newViewTop = scrollTopEquivalence * (view.container.context.scrollHeight - viewVerticalScrollSize)

        view.scrollTop(newViewTop)


        # console.log view
        # console.log "View stats: "
        # console.log "scrollHeight: ", view.container.context.scrollHeight
        # console.log "scrollTop:", view.scrollTop()
        # console.log "scrollBottom:", view.scrollBottom()
        # console.log "scrollWidth:", view.container.context.scrollWidth
        # console.log "scrollLeft:", view.scrollLeft()
        # console.log "scrollRight:", view.scrollRight()
        #
        # console.log "Editor stats: "
        # console.log "getScrollHeight:", @editor.component.getScrollHeight()
        # console.log "getScrollTop:", @editor.component.getScrollTop()
        # console.log "getScrollBottom:", @editor.component.getScrollBottom()
        # console.log "getScrollWidth:", @editor.component.getScrollWidth()
        # console.log "getScrollLeft:", @editor.component.getScrollLeft()
        # console.log "getScrollRight:", @editor.component.getScrollRight()

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

  addImages: (imgFiles, time, options) ->
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
      view = this
      img = $('<object/>')
        .attr('data', "#{file}?time=#{time}")
        .attr('type', "image/svg+xml")
        .attr('editorId', @editorId) # this attribute will be read by function that sends the selected text to the controller
        # see svgElementClicked(event)
        .attr('file', file)
        .load ->
          img = $(this)
          file = img.attr 'file'
          name = path.basename file, path.extname(file)
          if imageInfo.hasOwnProperty name
            info = imageInfo[name]
          else
            info = {}

          svgAttr = img.context.contentDocument.childNodes[0]
          if svgAttr is not undefined
            svgAttr = svgAttr.attributes
            info.origWidth = svgAttr.getNamedItem('width').nodeValue.replace("px", "")
            info.origHeight = svgAttr.getNamedItem('height').nodeValue.replace("px", "")
            img.attr('width', imageInfo.scale * info.origWidth)
            img.attr('height', imageInfo.scale * info.origHeight)

          imageInfo[name] = info
          img.attr('class', 'uml-image open-file copy-filename')

          if zoomToFit
            img.addClass('zoomToFit')

          view.scrollTop(options.scrollTo[0])
          view.scrollLeft(options.scrollTo[1])

      @container.append img
    @container.append '
    <script type="text/javascript">
      function svgElementClicked(event) {
        if(event.srcElement.tagName != "text")
          return;
        var editorId = event.view.frameElement.attributes.getNamedItem("editorId").nodeValue;
        var previewView = window.previews.filter(previewView => previewView.editorId === editorId);
        if(!previewView) return;
        previewView[0].selectTextInEditor(event.srcElement.innerHTML);
      }

      function insertScriptsInSVG(evt) {
          var svgDoc = evt.currentTarget.contentDocument;
          var svgObj = svgDoc.getElementsByTagName("svg")[0];

          var styleElement = svgDoc.createElementNS("http://www.w3.org/2000/svg", "style");
          styleElement.textContent = "text { cursor: pointer; } text:hover {stroke: black !important;}";
          svgObj.appendChild(styleElement);

          svgObj.addEventListener("click", svgElementClicked);
      }

      /* insert CSS and JS into generated SVG during runtime */
      var objs = document.getElementsByTagName("object");
      if(objs && objs.length > 0) {
        for(obj of objs) {
          obj.addEventListener("load", insertScriptsInSVG);
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
    edt = @editor
    buffer = edt.buffer

    # Sanitize input

    # sometimes the generated diagram has more characters than what was writen in the puml
    # e.g. 'alt' statement. It renders the condition of the alt surrounded by brackets. We must remove them
    # before we serch for the clicked text in the source file
    if text.charAt(0) == '['
      text = text.slice(1)
    if text.slice(-1) == ']'
      text = text.slice(0, -1)

    searchText = new DOMParser()
                  .parseFromString(text, "text/html").documentElement.textContent # decode html entities
                  .replace(/[-[\]{}()*+?.,\\^$|#]/g, '\\$&') # escape regex chars (findAll consider the input text as a regexp). \s are not escaped. see `replace` bellow
                  .replace(/\s+/g, '\\s\+') # spaces will be searched as possible sequences of spaces. in some scenarios plantuml replaces multiple spaces by a single space char

    buffer.findAll(searchText).then (ranges) ->
      if ranges.length > 0
        edt.clearSelections() # remove previous selections
        edt.setCursorBufferPosition(ranges[0].end) # move the existing cursor to the end of the first match
        for range in ranges
          edt.addSelectionForBufferRange(range) # add a selection for each matching text found in buffer

        pane = atom.workspace.paneForItem(edt)
        pane.activate() # focus the pane that contains the editor
        pane.activateItem(edt) # show the editor in pane (if there are multiple editors, the corresponding editor will be shown)

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

  renderUml: (options = {scrollTo: [0, 0]}) ->
    path ?= require 'path'
    fs ?= require 'fs-plus'
    os ?= require 'os'

    filePath = @editor.getPath()
    basename = path.basename(filePath, path.extname(filePath))
    format = 'svg' #the preview will always be SVG
    settingError = false
    directory = path.dirname(filePath)

    if atom.config.get('plantuml-toolkit.previewSettings.useTempDir')
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
      @addImages imgFiles, Date.now(), options
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
      @addImages(files, Date.now(), options)
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
