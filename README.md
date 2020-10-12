# BacCaml: The Meta-Hybrid Just-In-Time Compiler

[![Build Status](https://travis-ci.org/prg-titech/baccaml.svg?branch=develop)](https://travis-ci.org/prg-titech/baccaml)

Trace-based compilation and method-based compilation are two major compilation strategies in JIT compilers. In general, the former excels in compiling programs with more in-depth method calls and more dynamic branches, while the latter is a suitable wide range of applications.

This project aims at developing a fundamental mechanism for compiling with both trace-based and method-based strategies. Instead of developing a compiler for one particular language, we provide such a mechanism in a meta-compilation framework that generates a virtual machine with a JIT compiler from an interpreter definition of a programming language.

We are developing the BacCamel meta-compiler framework as a proof-of-concept, which is based on the [MinCaml compiler](https://github.com/esumii/min-caml).

## Prerequiements

You need the OCaml 4.10.0+ configured with 32bit mode. 

This is run only on Linux.

Plese follow these instructions:

```shell
$ opam switch create 4.10.0+32bit
$ opam install -y ppx_deriving ppx_inline_test
```

## Papers

- DLS'20: Yusuke Izawa, Hidehiko Masuhara. "Amalgamating Different JIT Compilations in a Meta-tracing JIT Compiler Framework". [url]

- Master's thesis: Yusuke Izawa, "Stack Hybridization: A Mechanism for Bridging Two Compilation Strategies in a Meta Compiler Framework". [[url]](https://3tty0n.github.io/baccaml-master-thesis.pdf)

- MoveVMs'19 workshop: Yusuke Izawa, Hidehiko Masuhara, Tomoyuki Aotani, "Extending a Meta-tracing Compiler to Mix Method and Tracing Compilation". [[url]](https://3tty0n.github.io/baccaml-programming-morevms-2019.pdf)

- Student Research Competition at &lt;Programming&gt; 2019: Yusuke Izawa, "BacCaml: The Meta-hybrid Just-In-Time Compiler". [[url]](https://3tty0n.github.io/baccaml-programming-src-2019.pdf)
