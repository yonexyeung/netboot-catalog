---
inclusion: always
---

# Git Workflow

## Branching Convention

- Never push directly to `main`.
- Always create a feature branch, commit there, then merge via PR.

### Branch Naming

```
feat/<short-description>     # New features
fix/<short-description>      # Bug fixes
docs/<short-description>     # Documentation changes
refactor/<short-description> # Code refactoring
chore/<short-description>    # Maintenance tasks
```

Examples:
- `feat/alpine-adapter`
- `fix/detection-regex`
- `docs/adapter-guide`
- `chore/update-dockerfile`

## Commit Messages

Use conventional commits:

```
<type>: <short summary>

<optional body>
```

Types: `feat`, `fix`, `docs`, `refactor`, `chore`, `test`

## Merge Strategy

- Create PR via `gh pr create`
- Squash merge preferred for feature branches
- Delete branch after merge

## Exceptions

- Initial project setup commits may go directly to `main` if explicitly requested by the user.
