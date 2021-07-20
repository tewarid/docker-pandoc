FROM pandoc/latex:2.14.1

# Install additional TeX packages such as those used by eisvogel template

RUN tlmgr option repository http://mirror.ctan.org/systems/texlive/tlnet \
    tlmgr update \
    && tlmgr install csquotes mdframed needspace sourcesanspro ly1 mweights \
    sourcecodepro titling pagecolor epstopdf zref footnotebackref \
    && apk add --update ghostscript

# Install Node and mermaid-filter

ENV CHROME_BIN="/usr/bin/chromium-browser" \
    PUPPETEER_SKIP_CHROMIUM_DOWNLOAD="true"

RUN apk add --update udev ttf-freefont chromium npm \
    && npm install -g mermaid-filter@1.4.5 --unsafe-perm=true
