# Entity Relationship

Status: PLANNED conceptual view; exact schemas/implementation pending.

```mermaid
erDiagram
    DOCUMENT ||--o{ PAGE : contains
    DOCUMENT ||--o{ OBJECT : contains
    DOCUMENT ||--o{ CONVERSATION : retains
    DOCUMENT ||--o{ HISTORY : checkpoints
    PAGE ||--o{ OBJECT : positions
    OBJECT }o--o{ ASSET : references
    CARD }o--o{ ASSET : retains

```
