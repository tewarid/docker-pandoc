FROM pandoc/latex

# Install additional TeX packages such as those used by eisvogel template

RUN tlmgr option repository http://mirror.ctan.org/systems/texlive/tlnet \
    tlmgr update \
    && tlmgr install csquotes mdframed needspace sourcesanspro ly1 mweights \
    sourcecodepro titling pagecolor epstopdf zref footnotebackref \
    && apk add --update ghostscript

# Install Node and mermaid-filter

RUN apk add --update npm \
    && npm install -g mermaid-filter@1.4.4 --unsafe-perm=true

ENV PATH /usr/lib/node_modules/.bin:$PATH
