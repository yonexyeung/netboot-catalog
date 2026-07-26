# Boot Recipe Specification v0.1

## Purpose

Define the canonical domain model for Boot Recipes.

## Design Principles

-   Distribution independent
-   Runtime independent
-   Human & machine readable
-   Versioned
-   Deterministic

## Core Domain

### ISO

Immutable input.

### Boot Recipe

The only core domain entity.

Contains: - Metadata - Detection Rules - Assets - Boot Parameters -
Validation Rules

### Boot Asset

Value object.

### Detection Rule

Declarative only.

### Boot Parameters

Template variables.

## Non-goals

No DHCP, HTTP, TFTP, Docker, Runtime, CLI, REST API or Web UI.

## Success

Any compatible engine can detect, extract, generate and boot.
