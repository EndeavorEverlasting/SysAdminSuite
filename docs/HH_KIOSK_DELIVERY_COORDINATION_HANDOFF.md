# H&H Kiosk Delivery Coordination Handoff

Status: reusable provider-neutral coordination contract  
Scope: technician / delivery-team / client communication only  
Live H&H addresses, names, phone numbers, ticket screenshots, and private evidence remain outside Git.

## Purpose

Provide one reusable communication sequence after a client confirms a kiosk delivery/install destination.

This document does not replace ticket authority, field acceptance, technical deployment contracts, or private evidence. It standardizes how confirmed client facts are relayed without forcing each coordinator or technician to rediscover the handoff.

## Evidence-before-relay rule

Only relay facts directly confirmed by an authoritative source.

Typical confirmed fields:

- ticket/request identifier;
- facility/program;
- street address;
- floor;
- room/department or clearly stated lobby/common-area destination;
- quantity;
- whether devices share the same destination;
- placement instructions;
- stairs/access/loading/security notes;
- contact-specific arrival-time request.

Unknown remains unknown. Do not invent a room number, hostname, ETA, access rule, or client preference.

## Coordination gates

Use explicit state:

- `LOCATION_GATE=RESOLVED | OPEN`
- `ACCESS_GATE=RESOLVED | OPEN | NOT_APPLICABLE`
- `DELIVERY_ETA=CONFIRMED | OPEN`
- `HOSTNAMES_OR_IDENTIFIERS=CONFIRMED | OPEN | NOT_REQUIRED_FOR_DELIVERY`
- `FIELD_COMPLETION=PROVED | OPEN`

A resolved location gate does not prove delivery completion.

## Recommended execution order

1. **Acknowledge the client**
   - confirm that the location details were received;
   - restate only the important confirmed placement details;
   - if ETA is still open, say it is being coordinated rather than guessing.

2. **Handoff to the delivery lead**
   - provide exact destination and placement;
   - provide access/loading constraints;
   - ask for the approximate arrival window if the client requested one.

3. **Handoff to field technicians**
   - provide the exact destination and placement;
   - state whether a separate room number is required;
   - include access notes;
   - state ETA as OPEN until delivery confirms it.

4. **Close the ETA loop**
   - once the delivery lead confirms the window, reply to the client on the existing thread;
   - relay the same ETA to technicians if it affects routing.

5. **Close only from evidence**
   - record actual arrival, placement, install completion, and functional validation from field evidence;
   - never use the client-confirmation email as installation proof.

## Client acknowledgement template

> Hi <CLIENT_NAME>,
>
> Thank you — this is exactly what we needed.
>
> I have the installation location noted as <ADDRESS / DESTINATION>, with <QUANTITY / PLACEMENT>. I also noted <ACCESS NOTES>.
>
> I’m coordinating the delivery timing with our delivery team now and will follow up with the approximate arrival time as soon as I have it confirmed.
>
> Thank you again,  
> <COORDINATOR_NAME>

## Delivery-lead handoff template

> Hi <DELIVERY_LEAD> — client location is confirmed for <REQUEST_ID>.
>
> Delivery/install destination:  
> <ADDRESS>  
> <CROSS-STREET / FACILITY CONTEXT>
>
> Placement: <PLACEMENT>  
> Access: <ACCESS NOTES>
>
> The client is asking for an approximate arrival time. Can you confirm the expected delivery window/ETA so I can reply to them?

## Technician handoff template

> <SITE / REQUEST_ID> — location confirmed.
>
> Address: <ADDRESS>  
> Install location: <FLOOR / ROOM / LOBBY / DEPARTMENT>  
> Quantity: <QUANTITY>  
> Placement: <PLACEMENT>  
> Access: <ACCESS NOTES>
>
> <ROOM-NUMBER RULE, if applicable>
>
> Delivery ETA: <OPEN | CONFIRMED WINDOW>
>
> Use this destination for field routing and installation unless a newer authoritative client update supersedes it.

## ETA follow-up template

> Hi <CLIENT_NAME>,
>
> Our delivery team has confirmed an approximate arrival window of <ETA / WINDOW>. We’ll plan for the equipment to be delivered and installed at the confirmed destination.
>
> Thank you,  
> <COORDINATOR_NAME>

## Proof ceiling

This handoff can prove communication consistency only.

It does **not** prove:

- delivery departure;
- arrival;
- successful receipt;
- installation completion;
- hostname assignment;
- application validation;
- kiosk functionality;
- ticket closure.

Those require separate field/ticket evidence.

## Parallel-agent rule

Private operational facts stay in the external H&H workspace.

Repository agents may improve this reusable template, but must not copy live names, addresses, ticket screenshots, or private client evidence into tracked source.

When a live coordination event occurs:

```text
client evidence
  -> private Drive/evidence record
  -> current relay draft
  -> delivery lead + technician handoff
  -> ETA confirmation
  -> field evidence
  -> ticket/operations closeout
```

This sequence is additive and can proceed independently from technical kiosk/device deployment work.
