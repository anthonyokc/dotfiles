" encoding=utf-8
" language en_US.utf8

let g:python3_host_prog='C:\Python\python.exe'
let g:python_host_prog='C:\Python\python.exe'

set number relativenumber

" Remappings
map <Enter> o<ESC>
map <S-Enter> O<ESC>

" Allows saving file as sudo within vim
cmap w!! w !sudo tee > /dev/null %

imap <C-BS> <C-W>

" Copying and Pasting
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

call plug#end()

