###
  Jitter, a CoffeeScript compilation utility

  The latest version and documentation, can be found at:
  http://github.com/TrevorBurnham/Jitter

  Copyright (c) 2010 Trevor Burnham
  http://iterative.ly

  Based on command.coffee by Jeremy Ashkenas
  http://jashkenas.github.com/coffee-script/documentation/docs/command.html

  Growl notification code contributed by Andrey Tarantsov
  http://www.tarantsov.com/

  Permission is hereby granted, free of charge, to any person
  obtaining a copy of this software and associated documentation
  files (the "Software"), to deal in the Software without
  restriction, including without limitation the rights to use,
  copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the
  Software is furnished to do so, subject to the following
  conditions:

  The above copyright notice and this permission notice shall be
  included in all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
  OTHER DEALINGS IN THE SOFTWARE.
###

# External dependencies
fs=            require 'fs'
path=          require 'path'
coffeelint=    require 'coffeelint'
optparse=      require './optparse'

if path.basename(process.argv[1]) == 'witter'
  targetlib = 'coco'
  target_ext = '.coco'
else
  targetlib = 'coffee-script'
  target_ext = '.coffee'

CoffeeScript=  require targetlib
{exec}=        require 'child_process'
{spawn}=         require 'child_process'
{puts, print}= try require 'util' catch e then require 'sys'
{q}=           require 'sink'

# Banner shown if jitter is run without arguments
BANNER= '''
  Jitter takes a directory of *.coffee files and recursively compiles
  them to *.js files, preserving the original directory structure.

  Jitter also watches for changes and automatically recompiles as
  needed. It even detects new files, unlike the coffee utility.

  This variant of Jitter accepts arguments of:
  
    ['-l', '--lint', 'run coffeelint on source directory before compiling']
    ['-t', '--test', 'run npm test on source directory after compiling']

  If passed a third parameter, node will be started with the script
  at this path.

  Usage:
    jitter [-lt] coffee-path js-path [nodeStartScript]
        '''
# Globals
options= {}
baseSource= baseTarget= ''
optionParser= null
isWatched= {}
nodeStartScript= ''
nodeProcess= null

exports.run= ->
  options = parseOptions()
  return usage() unless baseTarget
  compileScripts(options)

compileScripts= (options) ->
  dirs= Source: baseSource, Target: baseTarget
  for name, dir of dirs
    q path.exists, dir, (exists) ->
      unless exists
        die "#{name} directory '#{dir}' does not exist."
      else unless fs.statSync(dir).isDirectory()
        die "#{name} '#{dir}' is a file; Jitter needs a directory."
  q -> rootCompile options
  q postCompile
  q ->
    puts 'Watching for changes and new files. Press Ctrl+C to stop.'
    setInterval ->
        rootCompile options
    , 500

compile= (source, target, options) ->
  for item in fs.readdirSync source
    sourcePath= "#{source}/#{item}"
    continue if item[0] is '.'
    continue if isWatched[sourcePath]
    try
      if path.extname(sourcePath) is target_ext
        readScript sourcePath, target, options
      else if fs.statSync(sourcePath).isDirectory()
        compile sourcePath, target, options
    catch e

rootCompile= (options) ->
  compile(baseSource, baseTarget, options)

readScript= (source, target, options) ->
  compileScript(source, target, options)
  watchScript(source, target, options)

watchScript= (source, target, options) ->
  return if isWatched[source]
  isWatched[source]= true
  fs.watchFile source, persistent: true, interval: 250, (curr, prev) ->
    return if curr.mtime.getTime() is prev.mtime.getTime()
    compileScript(source, target, options)
    q postCompile

compileScript= (source, target, options) ->
  targetPath = jsPath source, target
  try
    code= fs.readFileSync(source).toString()
    try
      currentJS = fs.readFileSync(targetPath).toString()
    if options?.lint
      lint source
    js= CoffeeScript.compile code, {source, bare: options?.bare}
    return if js is currentJS
    writeJS js, targetPath
    if currentJS?
      puts 'Recompiled '+ source
    else
      puts 'Compiled '+ source
  catch err
    puts err.message
    notify source, err.message

jsPath= (source, target) ->
  filename= path.basename(source, path.extname(source)) + '.js'
  dir=      target + path.dirname(source).substring(baseSource.length)
  path.join dir, filename

writeJS= (js, targetPath) ->
  q exec, "mkdir -p #{path.dirname targetPath}", ->
    fs.writeFileSync targetPath, js

notify= (source, errMessage) ->
  basename= source.replace(/^.*[\/\\]/, '')
  if m= errMessage.match /Parse error on line (\d+)/
    message= "Parse error in #{basename}\non line #{m[1]}."
  else
    message= "Error in #{basename}."
  if process.platform is 'darwin' # growl for mac
    args= ['growlnotify', '-n', 'CoffeeScript', '-p', '2', '-t', "\"Compilation failed\"", '-m', "\"#{message}\""]
    exec args.join(' ')
  else # libnotify for linux
    args= ['notify-send', '-c', 'CoffeeScript', '-t', '2', "\"Compilation failed\"", "\"#{message}\""]
    exec args.join(' ')

lint= (source) ->
  lintProcess = spawn "./node_modules/coffeelint/bin/coffeelint", [ source ]
  lintProcess.stdout.on 'data', (data) ->
    print data
  lintProcess.stderr.on 'data', (data) ->
    print data

postCompile= ->
  if options?.test
    testProcess = spawn "npm", ["test"]
    testProcess.stdout.on 'data', (data) ->
      print data
    testProcess.stderr.on 'data', (data) ->
      print data
    testProcess.on 'exit', (code) ->
      runNodeScript()
  else
    runNodeScript()  

runNodeScript= ->
  # If already running node from previous compile, end it
  if nodeProcess
    nodeProcess.kill()

  if nodeStartScript
    nodeProcess = spawn "node", [ nodeStartScript ]
    nodeProcess.stdout.on 'data', (data) ->
      print data
    nodeProcess.stderr.on 'data', (data) ->
      print data
    nodeProcess.on 'exit', (code) ->  

parseOptions= ->
  optionParser= new optparse.OptionParser [
      ['-l', '--lint', 'run coffeelint on source directory before compiling']
      ['-t', '--test', 'run npm test on source directory after compiling']
      ['-b', '--bare', 'compile without the top-level function wrapper']
  ], BANNER
  options=    optionParser.parse process.argv
  [baseSource, baseTarget, nodeStartScript]= (options.arguments[arg] or '' for arg in [2..4])
  if /\/$/.test baseSource then baseSource= baseSource.substr 0, baseSource.length-1
  if /\/$/.test baseTarget then baseTarget= baseTarget.substr 0, baseTarget.length-1
  options

usage= ->
  puts optionParser.help()
  process.exit 0

die= (message) ->
  puts message
  process.exit 1

# http://stackoverflow.com/questions/5888477/
isSubpath= (parent, sub) ->
  parent = fs.realpathSync parent
  sub = fs.realpathSync sub
  sub.indexOf(parent) is 0
