#!/bin/sh
#
# Run Pandoc with eisvogel.tex template
#
# The following optional variables control template output:
#
# papersize=[letter | a4]               Specify page size as US Letter or A4
# blank-page-after-toc[=true]           Adds a blank page after table of contents
# blank-page-after-content[=true]       Adds a blank page after content
#
pandoc title.md example.md -f markdown -o out.pdf -N --toc --toc-depth 5 -F mermaid-filter --template ./eisvogel.tex --variable titlepage=true --variable secnumdepth=5 --variable papersize=a4 --variable caption-justification=centering
