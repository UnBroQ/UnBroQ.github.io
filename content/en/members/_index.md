---
title: 'Members'
date: 2026-01-19
type: landing

design:
  # Section spacing
  spacing: '5rem'

# Page sections
sections:
  - block: collection
    content:
      title: Top Co-authors
      filters:
        folders:
          - members
    design:
      view: article-grid
      fill_image: false
      columns: 3
      rows: 2
      show_date: false
      show_read_time: false
      show_read_more: false
  - block: collection
    content:
      title: Others
      filters:
        folders:
          - members
    design:
      view: article-grid
      fill_image: false
      columns: 3
      show_date: false
      show_read_time: false
      show_read_more: false
---
