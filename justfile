default:
  @just --list

build:
  zig build

run *args:
  zig build run -- {{args}}
