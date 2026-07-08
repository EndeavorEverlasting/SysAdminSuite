# Log Routing and Troubleshooting Plans

Troubleshooting plans under `examples/log-plan.*.json` are documentation artifacts. They route scenarios to log classes for authorized human review and do not execute commands.

Human-review examples, if an operator is separately authorized, should be copied and run by the operator outside the classifier. They are examples only; the classifier itself performs no live host log reads.

Deployment-owned evidence remains under `output/deployments/<deployment-id>/`. Host/audit/security logs remain on their systems of record and are never cleaned by this deployment lane.
