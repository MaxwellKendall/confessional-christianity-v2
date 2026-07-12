# PRD: Catechism-First Experience

## Summary

Replace user-facing "plans" with a catechism-first product model. A visitor should arrive from search, choose or land directly on a catechism, pick a starting question, experience the question with Scripture and prayer, and begin saving progress with as little friction as possible.

Internally, the app may still have assignments, pacing, sessions, and authored content pipelines. Publicly, users should see catechisms, sessions, progress, and milestones.

## Product Principle

The public object is the catechism. The private object is progress.

Users are not looking for a "plan." They are looking for the Westminster Shorter Catechism, Heidelberg Catechism, or catechisms for family worship. The app should expose the catechism first, then offer progress saving once the value is clear.

## Goals

- Help search visitors reach the "aha" moment within the first screen or first interaction.
- Let users start a catechism session without creating an account.
- Let users choose both the catechism and starting question.
- Save a first local progress track without account creation.
- Gate account creation only when the user asks for something that needs identity or durable server state.
- Replace user-facing "plans" language with "catechism," "progress," "session," and "milestones."
- Keep authored supporting materials, including prayers, commentary, and Bible readings, abstracted behind the catechism session.

## Non-Goals

- Do not require all catechisms to be implemented before changing the UX language.
- Do not remove internal program or assignment models in the first iteration.
- Do not build a full curriculum marketplace.
- Do not require account creation before a user can inspect content or complete a first session.

## Target Users

- A parent searching for "Westminster Catechism for kids."
- A homeschool parent who wants a structured but lightweight catechism routine.
- A church member searching for "Shorter Catechism question 1."
- A returning parent who wants to continue a child's catechism progress.

## The Aha Moment

The user should understand this quickly:

> This is the catechism, paired with Scripture and prayer, and I can keep track of progress through it.

The UI must make all four pieces visible:

- Catechism question and answer.
- Scripture proof text or Bible reading.
- Prayer or closing family worship prompt.
- Progress/milestone affordance.

## User-Facing Language

Avoid:

- Plan
- Program
- Assignment
- Configuration

Prefer:

- Catechism
- Continue
- Begin
- Session
- Progress
- Milestone
- Pacing

Examples:

- "Start a Program" becomes "Start the Shorter Catechism."
- "Eli's Plan" becomes "Eli's Shorter Catechism Progress."
- "Continue Today's Session" becomes "Continue the Shorter Catechism."
- "Configuration" becomes "Pacing."
- "The Plan Is Complete" becomes "Catechism Complete."

## Account Gate Recommendation

### Default: no account required

A user should be able to:

- Browse catechisms.
- Search or jump to any question.
- Start from question 1 or another question.
- Complete at least one session.
- Save local progress for one child or unnamed learner.
- Return on the same device and continue.

This should use `localStorage` or IndexedDB as anonymous local state.

### Soft account prompt

After local progress exists, show a non-blocking prompt:

> Progress is saved on this device. Create an account to keep it safe and use it anywhere.

This prompt should never block continuing the first local catechism track.

### Hard account gates

Require account creation only when the user requests one of these:

- Add a second child.
- Sync progress across devices.
- Share a child's progress with another adult.
- Restore progress after device/browser loss.
- Use server-backed reminders or emails.
- Manage multiple catechisms at once for the same household, if local complexity becomes high.

### Why the second child is a reasonable gate

Adding a second child changes the product from "try this catechism and keep my place" into household management. That is a natural point to ask for an account because:

- Identity becomes useful.
- The risk of losing local state becomes more painful.
- The UI now needs child switching and durable ownership.
- Sharing and permissions become relevant.

Do not gate on the first child. Gate on the second child, sync, sharing, or recovery.

## Anonymous Local Progress

### Requirements

- Store anonymous progress locally.
- Keep the copy honest: "Saved on this device."
- Allow conversion to an account later.
- Avoid collecting personal data before signup when possible.

### Suggested Local Shape

```json
{
  "version": 1,
  "activeCatechismId": "WSC",
  "learners": [
    {
      "localId": "local-primary",
      "displayName": "My child",
      "age": null,
      "tracks": [
        {
          "catechismId": "WSC",
          "currentQuestion": 2,
          "startedAtQuestion": 1,
          "startedAt": "2026-07-11T00:00:00.000Z",
          "milestones": {
            "1": {
              "state": "introduced",
              "introducedAt": "2026-07-11T00:00:00.000Z",
              "reviewCount": 0
            }
          }
        }
      ]
    }
  ]
}
```

### Conversion

When a user creates an account, migrate local progress to server rows. The confirmation copy should be:

> Your progress has been saved to your account.

If migration fails, keep local progress intact and retry.

## Catechism and Starting Point Input

The first-start flow should ask two things:

1. Which catechism?
2. Where do you want to begin?

### Catechism Input

Provide a searchable/selectable input with common options:

- Westminster Shorter Catechism
- Westminster Larger Catechism
- Heidelberg Catechism
- Catechism for Young Children

Initially, unavailable catechisms can appear as "coming later" or be omitted. Do not present unavailable catechisms as selectable.

### Starting Point Input

Allow:

- Start at Question 1.
- Search by keyword.
- Enter a question number.
- Continue from a detected local progress position.

Validation:

- The number must be within the catechism's available question range.
- If a user starts later than Q1, prior questions should remain unstarted, not auto-completed.
- The app should explain that they can go back at any time.

Example copy:

> Begin with Question 1, or jump to the question your family is already learning.

## Milestones

"Milestones" should replace "plans" only as a progress concept, not as the primary content object.

Recommended model:

- The catechism is the thing being studied.
- A session is today's interaction.
- A milestone is a question-level progress marker.

Milestone states:

- Not started
- Introduced
- Reviewing
- Mastered

Question milestones should carry the abstracted supporting materials:

- Catechism question and answer.
- Proof-text Scripture or Bible reading.
- Authored prayer.
- Optional commentary or parent note.

The UI should not ask the user to manage those pieces separately. It should say something like:

> Question 7 includes Scripture, prayer, and review.

## Primary User Flow

1. User lands on home or catechism page from search.
2. User sees actual catechism content immediately.
3. User chooses a catechism if not already on one.
4. User chooses a starting point.
5. User begins a session.
6. User completes the session.
7. App saves progress locally.
8. App offers account creation for durable sync, but does not block continuation.
9. User hits a hard gate only when adding a second child, syncing, sharing, or recovering.

## Home Page Requirements

- H1 should be catechism-specific or catechism-category-specific.
- First viewport should include actual catechism content, not only marketing copy.
- Primary CTA should start the catechism session.
- Secondary CTA should browse catechisms.
- Include proof of value: Scripture, prayer, progress.
- Do not mention "plans" in the unauthenticated homepage.

## Catechism Page Requirements

- Public route for each catechism.
- SEO metadata should target catechism-specific queries.
- Show question list or searchable question index.
- Show selected question with answer, proof texts, and related prayer if available.
- Include "Begin here" CTA for any question.
- Include "Save progress" only after interaction or as a secondary affordance.

## Session Requirements

- Session should work without authentication.
- Session should know catechism ID and starting question.
- Session should show:
  - Question and answer.
  - Scripture.
  - Prayer.
  - Progress/milestone update.
- Completing a session updates local progress if anonymous.
- Completing a session updates server progress if authenticated.

## Returning Anonymous User

If local progress exists:

- Home page should show "Continue the Shorter Catechism."
- Copy should indicate "Saved on this device."
- Offer "Create an account to keep progress safe" as a secondary action.

## Returning Authenticated User

If server progress exists:

- Home page should show child-specific progress.
- Copy should avoid "plan":
  - "Continue Clara's Shorter Catechism."
  - "Question 12 next."
  - "23 milestones completed."

## Data and Implementation Notes

Initial implementation can keep existing internal names:

- `ProgramDefinition`
- `catechism_assignments`
- `program_pacing`
- `/programs/...` routes

But public copy and route strategy should move toward:

- `/catechisms`
- `/catechisms/westminster-shorter-catechism`
- `/catechisms/westminster-shorter-catechism/session`

Migration can be staged:

1. Change user-facing copy.
2. Add public catechism-first pages.
3. Add anonymous local progress.
4. Add local-to-account migration.
5. Rename internal routes/models only if the old names keep causing confusion.

## Analytics

Track funnel events:

- `catechism_page_viewed`
- `question_previewed`
- `starting_point_selected`
- `anonymous_session_started`
- `anonymous_session_completed`
- `local_progress_saved`
- `account_prompt_seen`
- `account_created_from_progress`
- `second_child_gate_seen`
- `local_progress_migrated`

Primary success metrics:

- Visitor to first session start.
- First session start to completion.
- Completion to local progress saved.
- Local progress saved to return visit.
- Return visit to account creation.

## Acceptance Criteria

- A first-time visitor can start the Westminster Shorter Catechism without an account.
- A first-time visitor can choose question 1 or another valid starting question.
- Completing a session stores local progress.
- Returning on the same device shows a continue state.
- Adding a second child requires account creation.
- Creating an account migrates local progress.
- The unauthenticated UI does not use "plan" as the primary user-facing concept.
- Authenticated progress UI uses catechism/progress/milestone language.
- Existing authored prayers and Scripture integrations remain hidden behind the session experience.

## Open Questions

- Should the first anonymous learner ask for a child name, or default to "My child" until account creation?
- Should local progress support multiple catechisms before signup, or should that be a soft account prompt?
- Should "milestone" be visible as a label, or should the UI simply show hearts/checkmarks and "Question 7 mastered"?
- Should the catechism picker include disabled future catechisms for product signaling, or only currently usable catechisms?
