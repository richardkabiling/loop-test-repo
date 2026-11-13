# Infrastructure design

Read this in design step 4 when `infra` is selected (IaC, workload templates, environments or networking change). Output: `design/infra.md`.

## Sections

1. **Resources:** what's added or changed, per environment.
2. **Topology:** network paths, trust boundaries, data flows (diagram).
3. **Operability:** SLOs and SLIs, alerts, dashboards, runbooks, on-call impact.
4. **Security:** identities and least privilege, secrets handling, encryption, exposure.
5. **Cost:** estimate and budget alarms.
6. **Rollout:** plan output reviewed in the PR; apply from CI only; progressive delivery and rollback.

## Defaults and sources

- AWS Well-Architected pillars (operational excellence, security, reliability, performance efficiency, cost optimisation, sustainability) as the checklist: <https://aws.amazon.com/architecture/well-architected/>.
- SLOs: <https://sre.google/sre-book/service-level-objectives/>.
- The agent never applies (scoped `iac` rule; permission deny rules).

**Exit:** every resource has an owner, an SLO where relevant, least-privilege access, a cost estimate and a rollback path.
