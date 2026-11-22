## Agent conventions

1. **Naming.** PR and issue titles start with the project code, then the main change in plain words. The codes are FLW (family-librarian-web), LIB (librarian_agent), EVALS (librarian-agent-evals), and DATA (data-agent-demo). For example: `FLW: questions to five books`. Comments and reports name other PRs and issues the same way, as a link, never as a bare `#46`.
2. **Frontend evidence.** Any PR that changes the frontend embeds its screenshots inline in the PR body as images, not as links to cursor.com artifacts. The PNGs live on the orphan branch `pr-evidence` under `pr-<number>/`, never on the feature branch or main. Never force-push.
