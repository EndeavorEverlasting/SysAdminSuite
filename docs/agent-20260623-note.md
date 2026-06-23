# PR 46 tutorial polish note

This branch adds a small post-bundle dashboard polish layer for the PR 46 guided tutorial.

## Scope

- Loads `dashboard/css/tutorial-polish.css` after the main dashboard stylesheet.
- Loads `dashboard/js/tutorial-polish.js` after `dashboard/js/bundle.js`.
- Keeps the generated bundle unchanged.

## Intent

The patch corrects visible tutorial issues while minimizing risk to the existing dashboard build path. The generated bundle can still be rebuilt later from source once the team is ready to fold these changes directly into `dashboard/js/app.js` and rebuild `dashboard/js/bundle.js`.
