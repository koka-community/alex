# Alex: A Lexical Analyser Generator

[![CI](https://github.com/haskell/alex/actions/workflows/ci.yml/badge.svg)](https://github.com/haskell/alex/actions/workflows/ci.yml)

Alex is a tool for generating lexical analysers, also known as "lexers" and "scanners", in Haskell.
The lexical analysers implement a description of the tokens to be recognised in the form of regular expressions.
It is similar to the tools "lex" and "flex" for C/C++.

Share and enjoy!

> [!WARNING]
> This repository is a WIP.
> The plan is to reuse the generators from the Haskell language, but generate Koka code.
> Eventually we might transition to a more optimized workflow for Koka, without all of the extras we don't need. 
> Documentation is from the Haskell project
> Every once in a while we should sync from the upstream Haskell project, the methodology for doing so is still being determined.

## Documentation

Documentation is hosted on [Read the Docs](https://haskell-alex.readthedocs.io):

- [Online (HTML)](https://haskell-alex.readthedocs.io)
- [PDF](https://haskell-alex.readthedocs.io/_/downloads/en/latest/pdf/)
- [Downloadable HTML](https://haskell-alex.readthedocs.io/_/downloads/en/latest/htmlzip/)

For basic information of the sort typically found in a read-me, see the following sections of the docs:

- [About Alex](https://haskell-alex.readthedocs.io/en/latest/about.html)
- [Obtaining Alex](https://haskell-alex.readthedocs.io/en/latest/obtaining.html)
- [Contributing](https://haskell-alex.readthedocs.io/en/latest/contributing.html)
