# Project Overview

## Scope

Project: macUSB website (GitHub Pages static site).

The website is the public product site for macUSB and a documentation hub with practical guides.
It should stay modern, clear, SEO-oriented, and stable on desktop and mobile.

## Core objectives

- Present macUSB value proposition clearly on a concise landing flow.
- Support long-tail SEO for bootable macOS USB use cases.
- Preserve robust guide pages for Tiger Multi-DVD and PowerPC USB boot.
- Keep implementation framework-free (pure HTML/CSS/JS).

## Current landing page structure (`/index.html`)

- Hero with intro reveal animation and primary CTAs.
- Product section: `USB Creation`.
- Product section: `macOS Downloader`.
- `Why macUSB` block.
- `What It Creates` block.
- `Open Source` trust block.

## JavaScript architecture (current)

The runtime is split by scope instead of one monolithic file:

- `assets/js/core/*`: shared infrastructure used across primary pages.
- `assets/js/common/*`: reusable behavior loaded where needed.
- `assets/js/home/*`: homepage-only interactions.
- `assets/js/guides/*`: guide-only interactions.

Each HTML page must load only the scripts required by that page.
