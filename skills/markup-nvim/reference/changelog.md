<!-- Copied from CHANGELOG.md by scripts/docs.lua. Do not edit. -->

# Changelog

## [0.6.0](https://github.com/kawre/markup.nvim/compare/v0.5.0...v0.6.0) (2026-11-22)


### Features

* a picker core for any look, that moves like a buffer and like Snacks ([#40](https://github.com/kawre/markup.nvim/issues/40)) ([71456e4](https://github.com/kawre/markup.nvim/commit/71456e4c552cc74e480caf27e326d77dd5a64c9f))
* add display overrides to elements ([#41](https://github.com/kawre/markup.nvim/issues/41)) ([1754e47](https://github.com/kawre/markup.nvim/commit/1754e47e0d486781de890a47d47ae730896ccfe9))


### Performance Improvements

* picker rows that stay, Rust matching off the main thread, and resizes that keep up ([#43](https://github.com/kawre/markup.nvim/issues/43)) ([7a74223](https://github.com/kawre/markup.nvim/commit/7a742238afab9c64bcc10ec3cff205b7002884a3))
* size flex and grid items without throwing out their layout ([#38](https://github.com/kawre/markup.nvim/issues/38)) ([99e3fb9](https://github.com/kawre/markup.nvim/commit/99e3fb9bb04ccc9ad5d84d137f9532a1e51efad9))

## [0.5.0](https://github.com/kawre/markup.nvim/compare/v0.4.0...v0.5.0) (2026-11-21)


### ⚠ BREAKING CHANGES

* update keyed rows reactively and correct layout and cleanup ([#33](https://github.com/kawre/markup.nvim/issues/33))

### Features

* inert elements, a held cursor, the view's height, and half borders that follow their style ([#32](https://github.com/kawre/markup.nvim/issues/32)) ([389693b](https://github.com/kawre/markup.nvim/commit/389693b58b6f61a726ae23f0b358f2def2fb309e))


### Bug Fixes

* update keyed rows reactively and correct layout and cleanup ([#33](https://github.com/kawre/markup.nvim/issues/33)) ([85b0064](https://github.com/kawre/markup.nvim/commit/85b00646a5d87abb7ecbeca788ae9118467ab60e))
* what manual testing turns up: &lt;CR&gt; presses, margins, flex sizing, max_width and overflow ([#34](https://github.com/kawre/markup.nvim/issues/34)) ([92637ac](https://github.com/kawre/markup.nvim/commit/92637ac36ca352ce3da4a3196b139f970e2c8542))

## [0.4.0](https://github.com/kawre/markup.nvim/compare/v0.3.0...v0.4.0) (2026-11-20)


### Features

* flowering Nerd Font loaders, and pick to choose what is drawn ([#28](https://github.com/kawre/markup.nvim/issues/28)) ([da23a0c](https://github.com/kawre/markup.nvim/commit/da23a0c87c9802804ce23cb90af76539de1aab4f))

## [0.3.0](https://github.com/kawre/markup.nvim/compare/v0.2.0...v0.3.0) (2026-11-20)


### Features

* let clients check a supported markup.nvim version range ([#24](https://github.com/kawre/markup.nvim/issues/24)) ([e7a3c53](https://github.com/kawre/markup.nvim/commit/e7a3c532302491a611be6c5d276e19a218ae8cb0))

## [0.2.0](https://github.com/kawre/markup.nvim/compare/v0.1.0...v0.2.0) (2026-11-20)


### Features

* versions, releases with prebuilt engines, and the skill as a Claude Code plugin ([#18](https://github.com/kawre/markup.nvim/issues/18)) ([44db648](https://github.com/kawre/markup.nvim/commit/44db648f92285989208a72ab23531948b41a02ca))
