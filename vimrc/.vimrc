" Vim comes with quite a few default plugins
" which are not always needed so lets disable some of them
" for the sake of a little better startup time

let g:loaded_2html_plugin = 1
let g:loaded_getscript = 1
let g:loaded_getscriptPlugin = 1
let g:loaded_gzip = 1
let g:loaded_logiPat = 1
let g:loaded_matchparen = 1
let g:loaded_netrw = 1
let g:loaded_netrwPlugin = 1
let g:loaded_netrwSettings = 1
let g:loaded_rrhelper = 1
let g:loaded_tar = 1
let g:loaded_tarPlugin = 1
let g:loaded_vimball = 1
let g:loaded_vimballPlugin = 1
let g:loaded_zip = 1
let g:loaded_zipPlugin = 1

" some fine tuning
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

" The matchit plugin makes the % command work better, but it is not backwards
" compatible.
if has('syntax') && has('eval')
    packadd! matchit
endif

" ignore these for fzf
let $FZF_DEFAULT_COMMAND='find . \( -name node_modules -o -name .git \) -prune -o -print'

" plugins
call plug#begin()
    Plug 'preservim/nerdtree', { 'on':  'NERDTreeToggle' }
    Plug 'ryanoasis/vim-devicons'
    Plug 'mhinz/vim-startify'
    Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
    Plug 'junegunn/fzf.vim'
call plug#end()

" if in case of lazy loading
function! s:AfterEnter(t) abort
    echom "vim is ready"
    " block cursor in normal mode, i-beam cursor in insert mode, and underline cursor in replace mode
    if empty($TMUX)
        let &t_SI = "\<Esc>]50;CursorShape=1\x7"
        let &t_EI = "\<Esc>]50;CursorShape=0\x7"
        let &t_SR = "\<Esc>]50;CursorShape=2\x7"
    else
        let &t_SI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=1\x7\<Esc>\\"
        let &t_EI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=0\x7\<Esc>\\"
        let &t_SR = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=2\x7\<Esc>\\"
    endif
endfunction

" My auto commands
augroup vimrcEx
    au!
    " For all text files set 'textwidth' to 78 characters.
    autocmd FileType text setlocal textwidth=78
augroup END

augroup user_cmds
    au!
    autocmd VimEnter * call timer_start(30, function('s:AfterEnter'))
augroup END

" auto reload vimrc on save
autocmd! BufWritePost $MYVIMRC source $MYVIMRC | echom "Reloaded"

" Start NERDTree when Vim starts with a directory argument.
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 1 && isdirectory(argv()[0]) && !exists('s:std_in') |
            \ execute 'NERDTree' argv()[0] |  execute 'cd '.argv()[0] | endif

"My auto commands end

" Maps
let mapleader=' '

inoremap { {}<Esc>ha
inoremap [ []<Esc>ha
inoremap ( ()<Esc>ha

nnoremap <leader>f :Files<CR>
nnoremap <leader>e :NERDTreeToggle<CR>
nnoremap <leader>s :Ag<CR>
nnoremap <leader>t  :term<CR>

" Maps end
