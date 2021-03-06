exec vam#DefineAndBind('s:c','g:vim_addon_fcsh', '{}')
let s:c['mxmlc_default_args'] = get(s:c,'mxmlc_default_args', ['--strict=true'])

" author: Marc Weber <marco-oweber@gxm.de>

" usage example:
" ==============
" requires python!
" map <F2> :exec 'cfile '.fcsh#Compile(["mxmlc", "-load-config+=build.xml", "-debug=true", "-incremental=true", "-benchmark=false"])<cr>

" implementation details:
" ========================
" python is used to run a fcsh process. All mxmlc commands are passed to that
" process. The target compilation id is read automatically so targets are
" reused. All lines received from that process are written to the logfile
" until the prompt (fcsh) is reached again

" If you want to start hacking on this consider having a look at vim-addon-sbt
" which has a similar implementation


" alternatives
" ============
" This vim script is using shell scripts as client server
" http://www.vim.org/scripts/script.php?script_id=1793

" takes fcsh command
" mxmlc ...
" returns filepath pointing to file containing compilation result
" requires python

" TODO implement shutdown, clean up ?
"      support quoting of arguments
fun! fcsh#Compile(fcsh_command_list)

  let g:fcsh_command_list = a:fcsh_command_list

  if !has('python')
    throw "python support required to run fcsh process"
  endif

python << PYTHONEOF
import sys, tokenize, cStringIO, types, socket, string, os, re, vim
from subprocess import Popen, PIPE, STDOUT

if not globals().has_key('fcshCompiler'):

  # fcsh_dict keeps compilation ids
  fcsh_dict = {}

  class FCSHCompiler():
    """connects to the scion server by either TCP/IP or socketfile"""
    def __init__(self):
      self.tmpFile = vim.eval("tempname()")
      self.ids = {}
      # errors are print to stderr. We want to catch them!
      p = Popen(["fcsh"], \
            shell = False, bufsize = 1, stdin = PIPE, stdout = PIPE, stderr = STDOUT)

      self.fcsh_o = p.stdout
      self.fcsh_i = p.stdin


      self.waitForShell(None)
    
    def waitFor(self, pattern, out):
      """ wait until pattern is found in an output line. Write non matching lines to out """
      while 1:
        line = self.readLine()
        match = re.match(pattern, line)
        if match != None:
          return match
        elif out != None:
          out.write(line+"\n")

    def readLine(self):
      """ if line starts with "(fcsh)" return that partial line else return full
          Thus a "(fcsh) ..." line will be split into two parts: "(fcsh)" and " ..."
      line """
      read = ""
      for i in "(fcsh)":
        c = self.fcsh_o.read(1)
        if c == "\n":
          return read
        read = read + c
        if c != i:
          break

      if read == "(fcsh)":
        return read
      else:
        s = read + self.fcsh_o.readline()
        return s[:-1]

    
    def waitForShell(self, out):
      self.waitFor("\(fcsh\)", out)
    
    def mxmlc(self, args):
      out = open(self.tmpFile, 'w')
      cmd = " ".join(args)
      if self.ids.has_key(cmd):
        self.fcsh_i.write("compile "+self.ids[cmd]+"\n")
        self.fcsh_i.flush()
      else:
        self.fcsh_i.write(cmd+"\n")
        self.fcsh_i.flush()
        res = self.waitFor(" fcsh: Assigned (\d*) as the compile target id", out)
        self.ids[cmd] = res.group(1)

      self.waitForShell(out)
      out.close()
      return self.tmpFile


  fcshCompiler = FCSHCompiler()

f = fcshCompiler.mxmlc(vim.eval('g:fcsh_command_list'))
vim.command("let g:fcsh_result='%s'"%f)

PYTHONEOF

  " unlet g:fcsh_command_list
  " unlet g:fcsh_result
  return g:fcsh_result
endf


fun! fcsh#CompileRHS()
  let ef=
       \ '%A%f\(%l\)\:\ col\:\ %c\ %m'
       \.',%-Z%p^'
       \.',%-C%.%#'
       \.',%-GRecompile\:%.%#'
       \.',%-GReason\:%.%#'
  let ef = escape(ef, '"\')
  let target = '--target-player=10.0.0'
  if index(['mxml','as'], expand('%:e')) >= 0
    let args = ["mxmlc"] + s:c['mxmlc_default_args'] + [target,  expand('%')]
  else
    let args = ['mxmlc'] + [target]
  end
  let args = actions#ConfirmArgs(args,'mxmlc command line')
  return  ['exec "set efm='.ef.'" ',"exec 'cfile '.fcsh#Compile(".string(args).")"]
endfun
