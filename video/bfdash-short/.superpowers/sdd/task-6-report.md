# Task 6 Scope Creep Review

## Removal Attempt

Attempted to remove the undeclared setup changes from Task 6:
- Removed `setupFiles: ["./vitest.setup.ts"]` from `vitest.config.ts`
- Deleted `vitest.setup.ts`

## Test Results

### TitleCard.test.tsx without mock - FAILED

```
Error: Uncaught [Error: useCurrentFrame() can only be called inside a component that was registered as a composition. See https://www.remotion.dev/docs/the-fundamentals#defining-compositions]
```

**Command executed:**
```bash
npm test -- TitleCard.test.tsx
```

**Failure Location:** `src/components/TitleCard.tsx:9:17` - the component calls `useCurrentFrame()` unconditionally at the top level during render

**Issue:** The TitleCard component is fundamentally dependent on Remotion's `useCurrentFrame()` hook being available, which requires a composition context. The reviewer's assumption that `useCurrentFrame()` defaults to 0 outside a composition context is incorrect - it actively throws an error.

## Status

**BLOCKED** - Cannot remove the mock without refactoring TitleCard.tsx or its test. The mock was necessary, but it was an undeclared out-of-scope change.

## Recommendation

The proper fix requires one of:
1. Refactor TitleCard.tsx to accept frame as a prop (making it testable without Remotion context)
2. Refactor TitleCard.test.tsx to provide proper Remotion composition context
3. Mock the specific Remotion hooks locally in TitleCard.test.tsx (move mock from global setup to test file)

Note: The current implementation correctly requires the mock - this is not a false positive. The scope-creep issue is that the mock was added globally without declaring it as a requirement.
