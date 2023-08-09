" Vim comes with quite a few default plugins which are not always needed so
" lets disable some of them for the sake of a little better startup time
let g:highlightedyank_highlight_duration = 300
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
let g:startify_fortune_use_unicode = 0
let g:startify_session_persistence    = 1
let g:startify_update_oldfiles = 0 
let mapleader=' '
" syntax highlight for vim doc
let g:markdown_fenced_languages = ['vim', 'Help' ]

" Simplify the startify list to just recent files and sessions
let g:startify_lists = [
  \ { 'type': 'sessions',  'header': ['   Projects'] },
  \ { 'type': 'dir',       'header': ['   Recent files'] },
  \ ]


" some fine tuning
set autoindent
set bg=dark
set cursorline
set encoding=utf-8
set expandtab
set hlsearch
set ignorecase
set mouse=a
set nobackup
set nocompatible
set nowritebackup
set noswapfile
set number
set relativenumber
set shiftwidth=4
set showmatch
set smartcase
set softtabstop=4
set tabstop=4
set termguicolors
set textwidth=80
set is hls
set matchpairs+=<:>
syntax on

" Having longer updatetime (default is 4000 ms = 4 s) leads to noticeable
" delays and poor user experience.
set updatetime=300

" Always show the signcolumn, otherwise it would shift the text each time
" diagnostics appear/become resolved.
set signcolumn=yes

" NERDTree stuff
let g:NERDTreeDirArrowExpandable = ''
let g:NERDTreeDirArrowCollapsible = ''

" Start NERDTree when Vim starts with a directory argument.
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 1 && isdirectory(argv()[0]) && !exists('s:std_in') |
    \ execute 'NERDTree' argv()[0] | wincmd p | enew | execute 'cd '.argv()[0] | endif

" Close the tab if NERDTree is the only window remaining in it.
autocmd BufEnter * if winnr('$') == 1 && exists('b:NERDTree') &&
            \b:NERDTree.isTabTree() | quit | endif

" If another buffer tries to replace NERDTree, put it in the other window, and bring back NERDTree.
autocmd BufEnter * if bufname('#') =~ 'NERD_tree_\d\+' && bufname('%') !~ 'NERD_tree_\d\+' && winnr('$') > 1 |
    \ let buf=bufnr() | buffer# | execute "normal! \<C-W>w" | execute 'buffer'.buf | endif

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

" FZF stuff 
" let $FZF_PREVIEW_COMMAND="bat --style=numbers --color=always {}"
let $FZF_DEFAULT_COMMAND='find . \( -name node_modules -o -name .git \) -prune -o -print'
let $FZF_DEFAULT_OPTS = '--layout=reverse  --preview-window up'
" plugins
call plug#begin()
    Plug 'prettier/vim-prettier', { 'do': 'yarn install --frozen-lockfile --production' }
    Plug 'antoinemadec/coc-fzf'
    Plug 'joshdick/onedark.vim'
    Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
    Plug 'junegunn/fzf.vim'
    Plug 'machakann/vim-highlightedyank'
    Plug 'mhinz/vim-startify'
    Plug 'neoclide/coc.nvim', {'branch': 'release'}
    Plug 'preservim/nerdtree', { 'on':  'NERDTreeToggle' }
    Plug 'ryanoasis/vim-devicons'
    Plug 'sainnhe/everforest'
    Plug 'rust-lang/rust.vim'
call plug#end()

colorscheme everforest

" if in case of lazy loading
function! s:AfterEnter(t) abort
    echo "vim is ready"
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
    " For all text files set 'textwidth' to 80 characters.
    autocmd FileType text setlocal textwidth=80
    au BufRead,BufNewFile *.hbs set filetype=html
augroup END

augroup user_cmds
    au!
    autocmd VimEnter * call timer_start(30, function('s:AfterEnter'))
augroup END

" auto reload vimrc on save
autocmd! BufWritePost $MYVIMRC source $MYVIMRC 
"My auto commands end

" Custom Mappings
inoremap ( ()<Esc>ha
inoremap <esc> <nop>
inoremap [ []<Esc>ha
inoremap jk <esc>
inoremap { {}<Esc>ha
nnoremap -          :NERDTreeFind<CR>
nnoremap <leader>! :exe '!'.input('Enter system command: ')<CR>
nnoremap <leader>cp :let @+ = expand('%:p')<CR>:echo "path copied: " . @+<CR>
nnoremap <leader>e  :NERDTreeToggle<CR>
nnoremap <leader>ff :Files<CR>
nnoremap <leader>fg :GFiles<CR>
nnoremap <leader>fs :Rg<CR>
nnoremap <leader>ll :SClose<CR>
nnoremap <leader>t <c-z> 
nnoremap <leader>tt :terminal<CR>
nnoremap <nowait>H bveK
nnoremap <silent><nowait> <leader>fb  :Buffers<cr>
nnoremap <silent><nowait> <leader>fc  :Commands<cr>
nnoremap <silent><nowait> <leader>fl  :Lines<cr>
nnoremap gp :silent %!npx prettier --stdin-filepath %<CR>
nnoremap x "_x
" Maps end

" Use tab for trigger completion with characters ahead and navigate.
" NOTE: There's always complete item selected by default, you may want to enable
" no select by `"suggest.noselect": true` in your configuration file.
" NOTE: Use command ':verbose imap <tab>' to make sure tab is not mapped by
" other plugin before putting this into your config.
inoremap <silent><expr> <TAB>
            \ coc#pum#visible() ? coc#pum#next(1) :
            \ CheckBackspace() ? "\<Tab>" :
            \ coc#refresh()
inoremap <expr><S-TAB> coc#pum#visible() ? coc#pum#prev(1) : "\<C-h>"

" Make <CR> to accept selected completion item or notify coc.nvim to format
" <C-g>u breaks current undo, please make your own choice.
inoremap <silent><expr> <CR> coc#pum#visible() ? coc#pum#confirm()
            \: "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"

function! CheckBackspace() abort
    let col = col('.') - 1
    return !col || getline('.')[col - 1]  =~# '\s'
endfunction

" Use <c-space> to trigger completion.
inoremap <silent><expr> <c-@> coc#refresh()

" Use `[g` and `]g` to navigate diagnostics
" Use `:CocDiagnostics` to get all diagnostics of current buffer in location list.
nmap <silent> [g <Plug>(coc-diagnostic-prev)
nmap <silent> ]g <Plug>(coc-diagnostic-next)

" GoTo code navigation.
nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)
nmap <silent> gy <Plug>(coc-type-definition)
" Use K to show documentation in preview window.
nnoremap <silent> K :call ShowDocumentation()<CR>

function! ShowDocumentation()
    if CocAction('hasProvider', 'hover')
        call CocActionAsync('doHover')
    else
        call feedkeys('K', 'in')
    endif
endfunction

" Highlight the symbol and its references when holding the cursor.
autocmd CursorHold * silent call CocActionAsync('highlight')

" Symbol renaming.
nmap <leader>rn <Plug>(coc-rename)

" Formatting selected code.
xmap <leader>=  <Plug>(coc-format-selected)
nmap <leader>=  <Plug>(coc-format-selected)

augroup mygroup
    autocmd!
    " Setup formatexpr specified filetype(s).
    autocmd FileType typescript,json,javascript setl formatexpr=CocAction('formatSelected')
    " Update signature help on jump placeholder.
    autocmd User CocJumpPlaceholder call CocActionAsync('showSignatureHelp')
augroup end

" Applying code actions to the selected code block.
" Example: `<leader>aap` for current paragraph
xmap <leader>a  <Plug>(coc-codeaction-selected)
nmap <leader>a  <Plug>(coc-codeaction-selected)

" Remap keys for apply code actions at the cursor position.
nmap <leader>ac  <Plug>(coc-codeaction-cursor)
" Remap keys for apply code actions affect whole buffer.
nmap <leader>as  <Plug>(coc-codeaction-source)
" Apply the most preferred quickfix action to fix diagnostic on the current line.
nmap <leader>qf  <Plug>(coc-fix-current)

" Remap keys for apply refactor code actions.
nmap <silent> <leader>re <Plug>(coc-codeaction-refactor)
xmap <silent> <leader>r  <Plug>(coc-codeaction-refactor-selected)
nmap <silent> <leader>r  <Plug>(coc-codeaction-refactor-selected)

" Run the Code Lens action on the current line.
nmap <leader>cl  <Plug>(coc-codelens-action)

" Map function and class text objects
" NOTE: Requires 'textDocument.documentSymbol' support from the language server.

omap ac <Plug>(coc-classobj-a)
omap af <Plug>(coc-funcobj-a)
omap ic <Plcug>(coc-classobj-i)
omap if <Plug>(coc-funcobj-i)
xmap ac <Plug>(coc-classobj-a)
xmap af <Plug>(coc-funcobj-a)
xmap ic <Plug>(coc-classobj-i)
xmap if <Plug>(coc-funcobj-i)

" Remap <C-f> and <C-b> for scroll float windows/popups.
if has('nvim-0.4.0') || has('patch-8.2.0750')
    nnoremap <silent><nowait><expr> <C-f> coc#float#has_scroll() ? coc#float#scroll(1) : "\<C-f>"
    nnoremap <silent><nowait><expr> <C-b> coc#float#has_scroll() ? coc#float#scroll(0) : "\<C-b>"
    inoremap <silent><nowait><expr> <C-f> coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(1)\<cr>" : "\<Right>"
    inoremap <silent><nowait><expr> <C-b> coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(0)\<cr>" : "\<Left>"
    vnoremap <silent><nowait><expr> <C-f> coc#float#has_scroll() ? coc#float#scroll(1) : "\<C-f>"
    vnoremap <silent><nowait><expr> <C-b> coc#float#has_scroll() ? coc#float#scroll(0) : "\<C-b>"
endif

" Use CTRL-S for selections ranges.
" Requires 'textDocument/selectionRange' support of language server.
nmap <silent> <C-s> <Plug>(coc-range-select)
xmap <silent> <C-s> <Plug>(coc-range-select)

" Add `:Format` command to format current buffer.
command! -nargs=0 Format :call CocActionAsync('format')

" Add `:Fold` command to fold current buffer.
"command! -nargs=? Fold :call     CocAction('fold', <f-args>)

" Add `:OR` command for organize imports of the current buffer.
"command! -nargs=0 OR   :call     CocActionAsync('runCommand', 'editor.action.organizeImport')

" Mappings for CoCList
" Show all diagnostics.
 nnoremap <silent><nowait> <leader>cd  :<C-u>CocFzfList diagnostics<cr>
 nnoremap <silent><nowait> <leader>cm  :<C-u>CocFzfList marketplace<cr>
" Manage extensions.
" nnoremap <silent><nowait> <space>e  :<C-u>CocFzfList extensions<cr>
" Show commands.

" Find symbol of current document.
nnoremap <silent><nowait> <leader>co  :<C-u>CocFzfList outline<cr>
" Search workspace symbols.
" nnoremap <silent><nowait> <space>s  :<C-u>CocFzfList -I symbols<cr>
" Do default action for next item.
nnoremap <silent><nowait> <space>j  :<C-u>CocNext<CR>
" Do default action for previous item.
nnoremap <silent><nowait> <space>k  :<C-u>CocPrev<CR>
" Resume latest coc list.
nnoremap <silent><nowait> <space>p  :<C-u>CocFzfListResume<CR>





" custom functions 

" list blames for the current file/buffer
command! Blame normal!:let @a=expand('%')<CR>:let @b=line('.')<CR>:new<CR>:set bt=nofile<CR>:%!git blame -wM <C-R>a<CR>:<C-R>b<CR>

"list the openend buffers and copy filepath to clipboard
function! FzfBufferList()
    " Get the list of buffer names
  let buffer_list = []
  for buffer_number in range(1, bufnr('$'))
    if buflisted(buffer_number) && bufname(buffer_number) != '' && !isdirectory(bufname(buffer_number))
      call add(buffer_list, bufname(buffer_number))
    endif
  endfor

  " Create the fzf command and execute it in a blocking manner
  let selected_buffer = fzf#run({
        \ 'source': buffer_list,
        \ 'header': 'Select a buffer:',
        \ 'sink': function('CopyToClipboard')
        \ })
endfunction

" Function to copy the selected path to the clipboard
function! CopyToClipboard(selected_buffer)
  if !empty(a:selected_buffer)
    let @+ = a:selected_buffer
    echo "Copied to clipboard: " . a:selected_buffer
  endif
endfunction

" Create a custom command to trigger the buffer list
command! -nargs=0 FzfBufferList :call FzfBufferList()

