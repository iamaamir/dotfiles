" no need to be compatible with vi


" enable line numbers
" enable mouse
" indention
set autoindent
set cursorline
:highlight Cursorline cterm=bold ctermbg=black
set expandtab
set hlsearch
set ignorecase
set mouse=a
set nocompatible
set number
set relativenumber
set shiftwidth=4
set showmatch
set smartcase
set softtabstop=4
set tabstop=4
set textwidth=79
set termguicolors



syntax on

colorscheme habamax

if v:progname =~? "evim"
  finish
endif

" Get the defaults that most users want.
source $VIMRUNTIME/defaults.vim

if &t_Co > 2 || has("gui_running")
  " Switch on highlighting the last used search pattern.
  set hlsearch
endif

" Put these in an autocmd group, so that we can delete them easily.
augroup vimrcEx
  au!

  " For all text files set 'textwidth' to 78 characters.
  autocmd FileType text setlocal textwidth=78
augroup END

" Add optional packages.
"
" The matchit plugin makes the % command work better, but it is not backwards
" compatible.
if has('syntax') && has('eval')
  packadd! matchit
endif

" ignore these for fzf
let $FZF_DEFAULT_COMMAND='find . \( -name node_modules -o -name .git \) -prune -o -print'


call plug#begin()
    Plug 'preservim/nerdtree', { 'on':  'NERDTreeToggle' }
    Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
    Plug 'junegunn/fzf.vim'
call plug#end()

" if in case of lazy loading
function! s:load_plugins(t) abort
  echom "vim is ready"
endfunction

augroup user_cmds
  autocmd!
  autocmd VimEnter * call timer_start(30, function('s:load_plugins'))
augroup END
