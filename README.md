# automation-tools
1. ./projects/backup.sh
- Berfungsi untuk backup folder ./projects dalam bentuk tar.gz pada ./tmp/backups
- Dibuat berjalan via cron job setiap jam 23.00 

2. Instalasi nvim
Solusi: Download AppImage Neovim 0.11.3 yang benar

Berdasarkan mirror SourceForge, tersedia nvim-linux-x86_64.appimage untuk versi v0.11.3 (rilis stabil per 12 Juli 2025) 
SourceForge
+1
.

Kita bisa ambil dari mirror ini supaya lebih pasti:

# Hapus file nvim yang salah
sudo rm /usr/local/bin/nvim

# Download AppImage Neovim 0.11.3 dari mirror SourceForge
wget -O nvim.appimage https://sourceforge.net/projects/neovim.mirror/files/v0.11.3/nvim-linux-x86_64.appimage/download

# Pastikan ukurannya lebih dari 10 MB
ls -lh nvim.appimage

# Beri izin eksekusi
chmod u+x nvim.appimage

# Pindahkan ke PATH
sudo mv nvim.appimage /usr/local/bin/nvim

# Tes versi
nvim --version


Jika ukuran file tercantum ~11 MB, berarti download sukses.

Mengapa cara ini berhasil?

URL releases/latest/download/nvim.appimage sering salah karena GitHub mungkin tidak selalu menyediakan nvim.appimage alias generik.

Mirror SourceForge punya URL langsung ke versi stable v0.11.3, jadi aman dan valid 
SourceForge
.

Tutorial resmi juga menyarankan download menggunakan .../stable/nvim-linux-x86_64.appimage 
vonheikemen.github.io
GitHub
.

Langkah selanjutnya setelah Neovim 0.11.3 berhasil ter-install

Cek versi: nvim --version (harus ≥ 0.10)

Python support:

pip install --user --break-system-packages pynvim


Install Pyright untuk LSP debugging Python:

sudo npm install -g pyright

Oke, kita langsung bikin setup Neovim 0.11+ yang siap untuk:

Python coding (LSP, autocomplete, linting, formatting)

Git integration (status, diff, blame di Neovim)

Tampilan modern (tree, icons, statusline)

Aku buat pakai Lazy.nvim biar gampang install plugin.
Strukturnya rapi: semua plugin auto-install kalau belum ada.

1️⃣ Persiapan sistem

Jalankan ini dulu di terminal:

# Python support di Neovim
pip install --user --break-system-packages pynvim black isort flake8

# NodeJS untuk LSP dan plugin tertentu
sudo apt install nodejs npm -y

# Python LSP server (Pyright)
sudo npm install -g pyright

# Git LSP tools
sudo apt install git -y

2️⃣ Buat folder config Neovim
mkdir -p ~/.config/nvim
nvim ~/.config/nvim/init.lua

3️⃣ Tempel config ini di init.lua
-- =========================
-- Lazy.nvim Bootstrap
-- =========================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({

  -- Theme & UI
  { "folke/tokyonight.nvim", lazy = false, priority = 1000, config = function()
      vim.cmd("colorscheme tokyonight-night")
    end
  },
  { "nvim-lualine/lualine.nvim", dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("lualine").setup { options = { theme = "tokyonight" } }
    end
  },

  -- File explorer
  { "nvim-tree/nvim-tree.lua", dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("nvim-tree").setup()
      vim.keymap.set("n", "<C-n>", ":NvimTreeToggle<CR>")
    end
  },

  -- LSP & Completion
  { "neovim/nvim-lspconfig" },
  { "hrsh7th/nvim-cmp", dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip",
    },
    config = function()
      local cmp = require("cmp")
      cmp.setup({
        snippet = { expand = function(args) require("luasnip").lsp_expand(args.body) end },
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "buffer" },
          { name = "path" },
        }),
      })
    end
  },

  -- Git integration
  { "lewis6991/gitsigns.nvim", config = function()
      require("gitsigns").setup()
    end
  },
})

-- =========================
-- LSP Config (Python)
-- =========================
local lspconfig = require("lspconfig")
lspconfig.pyright.setup {
  capabilities = require("cmp_nvim_lsp").default_capabilities()
}

-- =========================
-- Basic settings
-- =========================
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.wrap = false
vim.opt.termguicolors = true
vim.g.mapleader = " "

-- Keymaps
vim.keymap.set("n", "<leader>ff", ":Telescope find_files<CR>")
vim.keymap.set("n", "<leader>fg", ":Telescope live_grep<CR>")
