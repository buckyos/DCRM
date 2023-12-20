```mermaid
stateDiagram-v2
    [*] --> Wait
    Wait --> Active
    Active --> End
    Wait --> Cancelled
    Active --> ChallengeSuccess
    Cancelled --> [*]
    End --> [*]
    ChallengeSuccess --> [*]

```

