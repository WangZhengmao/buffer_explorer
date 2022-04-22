"
if !has('python3')
  echo "Error: Required vim compiled with +python3 , please refer to https://confluence.nvidia.com/display/~mathisonw/buffer+explorer"
  finish
endif


python3 << EOF
import vim


class file_dir():
    def __init__(self,name="",parent=None):
        self.name=name
        self.parent=parent
        self.dirs={}
        self.files={}

    def get_full_name(self):
        if self.parent==None :
            return self.name
        return self.parent.get_full_name()+"/"+self.name

    def get_indent(self,indent):
        str=""
        for i in range(indent):
            str+="\t"
        return str

    def get_line_mark(self) :
        number=get_current_cache().get_value("line",default_value=-1,instance=self)%(26*26)
        h=int(number/26)
        l=number%26
        str=chr(h+97)+chr(l+97)
        vim.command('nnoremap <buffer> <nowait> %s :call Key_action("%s")<CR>' %(str,str))
        return " <"+str+"> "

    def get_files(self):
        return [ self.files[filename] for filename in sorted(self.files)]

    def get_dirs(self):
        return [ self.dirs[dirname] for dirname in sorted(self.dirs) ]

    def get_file_dirs(self):
        return self.get_files()+self.get_dirs()

    def to_print(self) :
        if self.is_valid() :
            file_new_line=int(vim.eval('get(g:, "bufferexplorer_file_newline", 1)'))
            if file_new_line > 1 :
                return True
            valid_cnt=0
            for file in self.get_files() :
                if file.is_valid() :
                    valid_cnt+=1
            if valid_cnt == 1  and file_new_line:
                return True
            for dir_ in self.get_dirs() :
                if dir_.is_valid() :
                    valid_cnt+=1
                    if valid_cnt>1 :
                        return True
            if valid_cnt == 1 :
                return False
            return True
        else:
            return False

    def to_show_sub(self):
        return True

    def get_relv_path(self):
        str=self.name
        if self.parent!=None and not self.parent.to_print():
            str=self.parent.get_relv_path()+"/"+str
        return str

    def on_screen(self):
        if self.parent==None:
            return True
        if self.parent.to_show_sub()==False:
            return False
        return self.parent.on_screen()


    def get_str(self,indent):
        return self.get_indent(indent)+self.get_relv_path()+self.get_mark()+"\n"

    def get_str_tree(self,indent=0,line_num=0):
        get_current_cache().set_value("line",line_num,instance=self)
        
        str=""
        if  self.to_print() :
            str=self.get_str(indent)
            line_num+=1
            indent+=1



        if self.to_show_sub() :
            for file_dir in self.get_file_dirs():
                str_,line_=file_dir.get_str_tree(indent,line_num)
                str+=str_
                line_num=line_

        return str,line_num

    def get_all_files(self):
        files=[self.files[filename] for filename in self.files]
        for dirname,dir_ in self.dirs.items() :
            files+=dir_.get_all_files()
        return files

    def get_root_dir(self):
        if self.parent==None:
            return self
        return self.parent.get_root_dir()

    def get_top_to_print(self):
        if self.parent==None :
            if self.to_print() :
                return self
            return None
        top_to_print=self.parent.get_top_to_print()
        if top_to_print != None :
            return top_to_print
        if self.to_print() :
            return self
        return None

    def action_all(self,cmd,cursor_line) :
        for dir_file in self.get_file_dirs() :
            dir_file.action_all(cmd,cursor_line)
        if self.to_print() :
            self.action(cmd,cursor_line)


    def is_valid(self) :
        return True



class file(file_dir) :
    def __init__(self,name="",parent=None,buffer=None):
        file_dir.__init__(self,name,parent)
        self.buffer=buffer

    def action(self,cmd,cursor_line):
        if cursor_line==get_current_cache().get_value("line",default_value=-1,instance=self) and self.on_screen():
            if cmd=="enter" or  cmd=="LeftMouse" :
                self.open_buffer()
            elif cmd=="x" : # remove buffer
                self.remove_buffer()
            elif cmd=="s" :
                self.save_buffer()

        if cmd=="as":
            self.save_buffer()
        if cmd=="ax":
            self.remove_buffer()
                
                

    def open_buffer(self,update_history=True) :
        switch_to_buffer(self,update_history)

    def remove_buffer(self) :
        if self.is_changed():
            print("change unsave")
        else:
            vim.command(":bw"+str(self.buffer.number))
        
    def save_buffer(self) :
        if self.is_changed() :
            vim.command("buffer"+str(self.buffer.number))
            vim.command("update!")
        

    def is_valid(self) :
        if self.buffer.valid==False : #deleted
            return False

        if self.name in self.parent.dirs :
            return False
        if (not buffer_explorer_name in self.name) and int(get_buffer_info(self.buffer.number,"listed"))>0 : 
            return True
        return False

    def is_changed(self) :
        return self.buffer.options["mod"]

    def get_mark(self):
        str=self.get_line_mark()
        vars=[]
        if self.buffer==get_current_cache().get_value("last_file").buffer :
            vars.append("&") #last open
        if self.is_changed() :
            vars.append("*")
        if int(vim.eval('getbufvar(%s,"&readonly")'%self.buffer.number))==1:
            vars.append("readonly")
        return str+" ".join(vars)

    def updatebuffer(self,buffer):
        self.buffer=buffer

    def focus_cursor(self) :
        vim.command(":"+str(get_current_cache().get_value("line",default_value=-1,instance=self)+explorer_start_line))


class dir (file_dir) :
    def __init__(self,name="",parent=None) :
        file_dir.__init__(self,name,parent)

    def add_buffer(self,buffer) :
        filename=buffer.name
        if len(filename) :
            filename=filename[1:]
        path_list=filename.split("/")
        return self.add_file(path_list,buffer)

    def add_file(self,path_list,buffer=None) :
        filename=path_list.pop(0) #
        if len(path_list) : #still have sub dir , filename is dir name here
            return self.mkdir(filename).add_file(path_list,buffer)
        else:
            if filename in self.files :
                self.files[filename].updatebuffer(buffer)
            else:
                self.files[filename]=file(filename,self,buffer)
            return self.files[filename]

    def mkdir(self,dirname) :
        if not dirname in self.dirs :
            self.dirs[dirname]=dir(dirname,self)
        return self.dirs[dirname]

    def is_valid(self):
        for filename,file in self.files.items() :
            if file.is_valid() :
                return True
        for dirname,dir_ in self.dirs.items() :
            if dir_.is_valid() :
                return True
        return False

    def to_show_sub(self):
        return get_current_cache().get_value("show",default_value=True,instance=self)

    def action(self,cmd,cursor_line):
        
        if cursor_line==get_current_cache().get_value("line",default_value=-1,instance=self) and self.on_screen() :
            if cmd=="enter" or cmd=="LeftMouse" : #hidden or show
                show=self.to_show_sub()==False
                get_current_cache().set_value("show",value=show,instance=self)
                
            elif cmd=="s" :
                self.action_all("as",cursor_line)
            elif cmd=="x" :
                self.action_all("ax",cursor_line)

        if cmd=="f": #fold
            show=self.get_top_to_print().to_show_sub()==False
            get_current_cache().set_value("show",value=show,instance=self)
                    
                

    def get_mark(self):
        str=""
        if self.to_show_sub() :
            str+= "/"
        else:
            str+= "/..."
        str+=self.get_line_mark()
        return str



class status_cache (object) : #this will be instanced per tab/window to save it's status
    def __init__(self) :
        self.vars={}

    def get_value(self,key,default_value=None,instance="global") :
        instance_vars=get_value_from_dict(self.vars,instance,{})
        return get_value_from_dict(instance_vars,key,default_value)

    def set_value(self,key,value,instance="global") :
        instance_vars=get_value_from_dict(self.vars,instance,{})
        instance_vars[key]=value
        


if __name__=="__main__" :
    
    root_dir=dir()
    buffer_explorer_name="__Buffer_Explorer__"
    explorer_start_line=2 #1st line is for title

    def get_tab_win_id():
        tab_num=vim.current.tabpage.number
        win_number=vim.current.window.number
        return "tab"+str(tab_num)+"win"+str(win_number)

    def get_value_from_dict(dict_,key,default_value=None) :
        if not key in dict_ :
            dict_[key]=default_value
        return dict_[key]

    tab_win_caches={}
    def get_current_cache() :
        global tab_win_caches
        return get_value_from_dict(tab_win_caches,get_tab_win_id(),status_cache())

    def get_buffer_explorer_name():
        return buffer_explorer_name+get_tab_win_id()
    
    def load_buffer():
        for buffer in vim.buffers :
            root_dir.add_buffer(buffer)
    
    def switch_to_buffer(file,update_history=True):
        file_history=get_current_cache().get_value("file_history",root_dir.get_all_files())
        if file.is_valid():
            if update_history :
                if file in file_history :
                    file_history.remove(file)
                file_history.insert(0,file)
            vim.command(":b"+str(file.buffer.number))
        else:
            if file in file_history :
                file_history.remove(file)
            print("not a file")


    def buffer_prev_next(step):
        file_history=get_current_cache().get_value("file_history",root_dir.get_all_files())
        history_size=len(file_history)
        #reorder and remove invalid
        index=history_size+step
        new_history=[]
        for i in range(history_size) :
            index%=history_size
            file_=file_history[index]
            index+=1
            if file_.is_valid():
                new_history.append(file_)

        if len(new_history) :
            get_current_cache().set_value("file_history",new_history)
            new_history[0].open_buffer(False)
        else :
            print("no opened files")

        refreash()
    
    def back():
        get_current_cache().get_value("last_file").open_buffer(False)
        refreash()

    def buffer_explorer():
        if  get_buffer_explorer_name() in vim.current.buffer.name :
            back()
        else:
            vim.command(":set hidden")
            get_current_cache().set_value("last_file",root_dir.add_buffer(vim.current.buffer))
            #switch to buffer explorer
            vim.command(":e! "+get_buffer_explorer_name())
            vim.command(":setlocal filetype=buffer_explorer")
            vim.command(":setlocal noswapfile")
            vim.command(":setlocal bufhidden=delete")
            vim.command(":setlocal buftype=nowrite")
            vim.command(":setlocal nobuflisted")
            show_buffer_list()
            get_current_cache().get_value("last_file").focus_cursor()
            vim.command('call Set_buffer_attr()')
    
    def show_buffer_list():
        string,line=root_dir.get_str_tree()
        lines=string.split("\n")
        vim.command("setlocal modifiable")
        buffer_explorer_bufer=vim.current.buffer
        vim.command('let b:save_pos = getpos(".")')
        del buffer_explorer_bufer[:] 
        buffer_explorer_bufer[0]="Buffer explorer  .f:fold    .x:close    .s:save    .ax:close all    .as:save all"
        buffer_explorer_bufer.append(lines)
        vim.command("setlocal nomodifiable")
        vim.command('call setpos(".", get(b:, "save_pos", getpos(".")))')

    
    
    def get_buffer_info(buffer_num,key=None) :
        buffer_info=vim.eval('getbufinfo(%s)' %buffer_num)
        if key==None:
            return buffer_info[0]
        return buffer_info[0][key]
        
    
    def take_action():
        row=int(get_buffer_info(vim.current.buffer.number,"lnum"))
        cmd=vim.eval("a:cmd")
        root_dir.action_all(cmd,row-explorer_start_line)
        refreash()
    
    def key_action():
        key=vim.eval("a:key")
        h=ord(key[0])-97
        l=ord(key[1])-97
        line=h*26+l
        row=int(get_buffer_info(vim.current.buffer.number,"lnum"))
        #find the nearest line to cursor whose mark is key
        k=int((row-line+26*26/2)/26/26)
        real_line=k*26*26+line
        print(real_line)
        vim.command(":"+str(real_line+explorer_start_line))
        root_dir.action_all("enter",real_line)
        refreash()
    
    def refreash():
        if buffer_explorer_name in vim.current.buffer.name : #still in buffer explorer
            if root_dir.is_valid():
                show_buffer_list()
            else :
                vim.command("q!")
    
    
EOF
function! Set_buffer_attr()
   nnoremap <buffer> <nowait> <CR> :call Take_action("enter")<CR>
   nnoremap <buffer> <nowait> .x :call Take_action("x")<CR>
   nnoremap <buffer> <nowait> .s :call Take_action("s")<CR>
   nnoremap <buffer> <nowait> .f :call Take_action("f")<CR>
   nnoremap <buffer> <nowait> .ax :call Take_action("ax")<CR>
   nnoremap <buffer> <nowait> .as :call Take_action("as")<CR>
   nnoremap <buffer> <nowait> <2-LeftMouse> <LeftMouse>:call Take_action("LeftMouse")<CR>

   syntax  match bufferexplorerdirectory "\S*/" contains=buffer_explorer
   syntax  match bufferexplorerdirectory_ "\S*/\.\.\. " contains=buffer_explorer
   syntax  match bufferexplorerfile  "[A-Za-z0-9._-]* " contains=buffer_explorer
   syntax  match keyshortcut     "<[a-z]*>" contains=buffer_explorer
   syntax  match bufferexplorertitle "^Buffer explore.*$" contains=buffer_explorer

   highlight bufferexplorertitle cterm=BOLD  gui=BOLD ctermfg=red guifg=red
   highlight bufferexplorerdirectory  ctermfg=green guifg=green
   highlight bufferexplorerdirectory_ cterm=BOLD  gui=BOLD ctermfg=green guifg=green
   highlight keyshortcut cterm=BOLD  gui=BOLD
   highlight bufferexplorerfile ctermfg=yellow guifg=yellow

   setlocal nocursorline
   setlocal nocursorcolumn

endfunction

function! Buffer_explorer()
    python3 buffer_explorer()

    "call setpos('.', get(b:, 'save_pos', getpos(".")))
endfunction

function! Back()
    python3 back()
endfunction

function! Take_action(cmd)
    python3 take_action()
endfunction

function! Key_action(key)
    python3 key_action()
endfunction

function! Loadbuffer()
    python3 load_buffer()
endfunction

function! Prev_buffer()
    python3 buffer_prev_next(-1)
endfunction

function! Next_buffer()
    python3 buffer_prev_next(1)
endfunction

augroup buffer_explorer
autocmd BufNewFile,BufRead * call Loadbuffer()
augroup END

