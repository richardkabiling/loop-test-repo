# API / contract design

Read this in design step 4 when `api` is selected (an HTTP/RPC/event API or a library's public surface changes). Output: `design/api.md` plus the contract diff (`openapi.yaml`, `*.proto`, `schema.graphql`, `asyncapi.yaml` or the exported types).

## Sections

1. **Consumers:** who calls this and how (first-party UI, partners, other services).
2. **Contract changes:** resources and endpoints, messages or types, written contract-first as a diff against the current contract.
3. **Errors:** the error model, status codes and retry semantics.
4. **Compatibility:** additive vs breaking changes. Breaking changes need a versioning plan, a deprecation window and an ADR.
5. **Security:** authn/authz per operation, rate limits, input validation at the boundary.
6. **Examples:** request and response examples for each acceptance criterion; these become contract tests (Pact or provider verification).

## Defaults and sources

- OpenAPI 3.1 contract in the repo: <https://spec.openapis.org/oas/v3.1.0>.
- API design guidance: Google AIPs <https://google.aip.dev/>; Zalando RESTful API guidelines <https://opensource.zalando.com/restful-api-guidelines/>.
- Consumer-driven contract tests: <https://docs.pact.io/>.
- Breaking-change check in CI (`oasdiff`, `buf breaking`).

**Exit:** the contract diff is written; every change is classified additive or breaking; examples cover every acceptance criterion; consumers are named.
