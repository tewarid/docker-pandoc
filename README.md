# Pandoc Dockerfile

Creates a Docker image with Pandoc, TeX packages to run the [eisvogel](https://github.com/Wandmalfarbe/pandoc-latex-template/) template, Node.js, and [mermaid-filter](https://github.com/raghur/mermaid-filter).

## Pull image from Docker

To fetch the latest automated build image from Docker Hub

```bash
docker pull tewarid/pandoc
```

## Build Docker image

To build a new image

```bash
docker build -t pandoc-image .
```

## Run Pandoc

Assuming you have a bash script on the host such as

```bash
pandoc title.md doc.md -f markdown -o doc.pdf --toc -F mermaid-filter --template ./eisvogel.tex --variable titlepage=true
```

Here's how you can invoke it in a Docker container

```bash
docker run -v `pwd`:/workdir -w /workdir -i -t --name pandoc-container pandoc-image ./topdf.sh
```

To run the same script again

```bash
docker start -a -i pandoc-container
```

Remove the container when no longer needed

```bash
docker rm pandoc-container
```

## Known Issues

- Calling [mermaid.cli](https://github.com/mermaidjs/mermaid.cli) as root (default user in a Docker container) fails with the error

    ```text
    [0202/115116.882391:ERROR:zygote_host_impl_linux.cc(88)] Running as root without --no-sandbox is not supported. See https://crbug.com/638180.
    ```

    To fix it, file [index.bundle.js](index.bundle.js) needs to be patched, so that it launches puppeteer thus

    ```javascript
    const browser = yield puppeteer.launch({args: ['--no-sandbox']});
    ```
