" encoding=utf-8
" language en_US.utf8

if !exists('g:os')
    if has('win32') || has('win16')
        let g:os = 'Windows'
    else
        let g:os = substitute(system('uname'), '\n', '', '')
    endif
endif

if g:os == 'Darwin'
    " mac stuff
endif

if g:os == 'Linux'

 let g:python3_host_prog='/usr/bin/python3'
    let g:python_host_prog='/usr/bin/python3'
endif

if g:os == 'Windows'
    let g:python3_host_prog='C:\Python\python.exe'
    let g:python_host_prog='C:\Python\python.exe'
endif


set number relativenumber

" Remappings
" Map the leader key to a semicolon.
let mapleader = ';'
map <Enter> o<ESC>
map <S-Enter> O<ESC>

" Allows saving file as sudo within vim
cmap w!! w !sudo tee > /dev/null %

imap <C-BS> <C-W>

" Copying and Pasting (requires vim-gtk)
vmap <Leader>y "+y
vmap <Leader>d "+d
nmap <Leader>yy "+yy
nmap <Leader>p "+p
nmap <Leader>P "+P
vmap <Leader>p "+p
vmap <Leader>P "+P

noremap! <C-BS> <C-w>
noremap! <C-h> <C-w>

nnoremap <Leader>rm :call delete(expand('%')) \| bdelete!<CR>
nnoremap <Leader><space> :noh<cr>
 
" Install PlugInstall for Vim if not already installed:
let data_dir = has('nvim') ? stdpath('data') . '/site' : '~/.vim'
if empty(glob(data_dir . '/autoload/plug.vim'))
  silent execute '!curl -fLo '.data_dir.'/autoload/plug.vim --create-dirs  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

call plug#begin()

" Plug 'sirver/ultisnips'
" let g:UltiSnipsSnippetDirectories=['my-snippets', 'UltiSnips']
" let g:UltiSnipsExpandTrigger = '<tab>'
" let g:UltiSnipsJumpForwardTrigger = '<tab>'
" let g:UltiSnipsJumpBackwardTrigger = '<s-tab>'

Plug 'honza/vim-snippets'

Plug 'lervag/vimtex'
let g:tex_flavor='latex'
let g:vimtex_quickfix_mode=0
set conceallevel=1
let g:tex_conceal='abdmg'

Plug 'tpope/vim-surround'
" LaTeX Shortcuts
     let g:surround_{char2nr('(')} = "(\r)"
     let g:surround_{char2nr(')')} = "(\r)"
     let g:surround_{char2nr('{')} = "{\r}"
     let g:surround_{char2nr('}')} = "{\r}"
"     let g:surround_{char2nr('B')} = "\\left(\r\\right)"
"     let g:surround_{char2nr('{')} = "\\left[\r\\right]"
"     let g:surround_{char2nr('}')} = "\\left[\r\\right]"
"     let g:surround_{char2nr('r')} = "{\r}"
"     let g:surround_{char2nr('d')} = "\\frac{\r}{;}"
"     let g:surround_{char2nr('D')} = "\\dfrac{\r}{;}"
"     let g:surround_{char2nr('m')} = "\\(\r\\)"
"     let g:surround_{char2nr('u')} = "\\textbf{\r}"
"     let g:surround_{char2nr('U')} = "\\emph{\r}"
"     let g:surround_{char2nr('p')} = "\\frac{\\partial{\r}}{\\partial{;}}"
"     let g:surround_{char2nr('R')} = "\\underbrace{\r}_{f}"

Plug 'asvetliakov/vim-easymotion'
    map <Leader> <Plug>(easymotion-prefix)

Plug 'tpope/vim-repeat'

Plug 'KeitaNakamura/tex-conceal.vim'
    set conceallevel=1
    let g:tex_conceal='abdmg'
    hi Conceal ctermbg=none

Plug 'sedm0784/vim-you-autocorrect'
    
inoremap <C-l> <c-g>u<Esc>[s1z=`]a<c-g>u

Plug 'preservim/nerdtree'
    let NERDTreeWinSize = 150
    let NERDTreeShowHidden = 1
    set modifiable
" Plug 'numEricL/nerdtree-live-preview'

Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'

Plug 'nvim-lua/plenary.nvim'
    Plug 'ThePrimeagen/harpoon', { 'branch': 'harpoon2' }
    Plug 'nvim-telescope/telescope.nvim', { 'tag': '0.1.6' }

Plug 'R-nvim/R.nvim'
Plug 'R-nvim/cmp-r'
	" remapping the basic :: send line
	nmap , <Plug>RDSendLine
	" remapping selection :: send multiple lines
	vmap , <Plug>RDSendSelection
	" remapping selection :: send multiple lines + echo lines
	vmap ,e <Plug>RESendSelection
" install plugin :: using vim-plug
Plug 'rizzatti/dash.vim'
" remap search key
nmap <silent> <leader>d <Plug>DashSearch<CR>
Plug 'chrisbra/csv.vim'

" Completions
Plug 'ncm2/ncm2'
Plug 'roxma/nvim-yarp', { 'do': 'pip install -r requirements.txt' }
Plug 'jalvesaq/Nvim-R'
Plug 'gaalcaras/ncm-R'

" Optional: for snippet support
" Further configuration might be required, read below
Plug 'ncm2/ncm2-ultisnips'

" Optional: better Rnoweb support (LaTeX completion)
Plug 'lervag/vimtex'

call plug#end()

