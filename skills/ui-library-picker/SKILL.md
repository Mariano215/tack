---
name: ui-library-picker
description: Choose a UI component library for a web project. Covers shadcn/ui, coss ui, AlignUI, daisyUI, HeroUI and Ant Design. Use when starting a frontend, when the user asks which UI library, component library or UI kit to use, or names one of these libraries. Use it before installing one. Not for projects that already ship a component library; use that one.
---

# UI library picker

Pick one library, say why in one sentence, and install it with the command
below. The facts in the table were checked against each library's official
docs on 2026-11-15. Versions move fast: before you install, re-check the row
you picked with Context7 (`resolve-library-id`, then `query-docs` for the
install page). If the docs disagree with this table, follow the docs and say
so.

## First, the rules that decide most cases

1. **The project already has a component library** (check `package.json`
   and `components.json`): use it. Do not add a second one.
2. **Not React** (Vue, Svelte, Angular, Astro, Rails, Laravel, plain HTML):
   daisyUI. It is the only one here that works with any framework. For Vue
   with an enterprise admin, Ant Design Vue is a separate port of Ant Design.
3. **Enterprise admin, dense forms and tables, no Tailwind**: Ant Design.
4. **React with Tailwind v4, and you want to own the code**: shadcn/ui. Pick
   coss ui instead for its look (Cal.com style) or its extra status tokens.
5. **React 19 with Tailwind v4, and you want a package with upgrades rather
   than copied code**: HeroUI.
6. **The client has an AlignUI Figma file, or pays for AlignUI Pro**:
   AlignUI. Its free components are MIT, but most of its value (the Figma
   library and the Pro blocks) is paid, so without either, shadcn/ui is the
   simpler choice.
7. **A brand to match**: load the brand's design tokens first, if your
   profile has a design-system skill. Brand tokens beat any library's
   defaults.

## The libraries

| | Frameworks | Styling | Ships as | License | Accessibility | Install |
|---|---|---|---|---|---|---|
| **shadcn/ui** | React (Next.js, Vite, Remix) | Tailwind v4 and CSS variables, on Base UI (the default) or Radix | Code copied into the repo by a CLI | MIT | Base UI or Radix primitives | `npx shadcn@latest init` (Radix: `--base radix`) |
| **coss ui** | React | Tailwind v4 and Base UI, shadcn variables plus info, success and warning | Copied through the shadcn registry | MIT | Base UI primitives | new: `pnpm dlx shadcn@latest init @coss/style`, existing: `pnpm dlx shadcn@latest add @coss/ui` |
| **AlignUI** | React | Tailwind v4.1 and Radix, CSS custom properties | Copied source blocks, Tailwind set up by a CLI | Free components MIT (they ship in the official MIT starter repos); Pro components, blocks and Figma library are paid under AlignUI's own terms | Claims WCAG compliance, built on Radix | `npx @alignui/cli tailwind`, then each component's Radix package |
| **daisyUI** | Any (pure CSS) | Tailwind plugin with semantic class names, no JavaScript | npm package or CDN | MIT | None built in. You add focus handling and ARIA yourself | `npm i -D daisyui@latest`, then `@plugin "daisyui";` in the CSS |
| **HeroUI** | React 19 and newer | Tailwind v4 and React Aria Components | npm package | Apache-2.0 since April 2026 (MIT before, as NextUI and HeroUI v2) | React Aria | `npm i @heroui/styles @heroui/react` |
| **Ant Design** | React (a separate Vue port exists) | Its own design tokens through `ConfigProvider`, no Tailwind | npm package | MIT | Not stated in the docs | `npm install antd --save` |

## Where each one goes wrong

- **shadcn/ui and coss ui**: you own the copied code, so upstream fixes do not
  arrive on their own. Re-run the CLI to pull a component again.
- **daisyUI**: modals, comboboxes, menus and focus traps need JavaScript and
  ARIA that daisyUI does not ship. Use native `<dialog>` and test with a
  keyboard.
- **HeroUI**: needs React 19 and Tailwind v4. Older apps cannot use it
  without an upgrade.
- **Ant Design**: its own look is strong. A custom brand or a Tailwind-first
  site fights it. Theme it through `ConfigProvider` seed tokens
  (`colorPrimary`, `borderRadius`), not CSS overrides.
- **AlignUI**: the free components are MIT, but the Pro components and Figma
  library are paid under AlignUI's own terms. If a client project uses Pro,
  confirm who holds the license before you ship.
- **HeroUI**: Apache-2.0 asks you to keep its NOTICE and license text and to
  mark files you change. That is fine for client work, but it is more than
  MIT asks for.

## Done means

- One library is chosen, with a one-sentence reason that names the rule above
  that decided it.
- The install row was re-checked with Context7 before the install ran.
- Its theme maps to the project's brand tokens, if the project has any.

Sources (2026-11-15): ui.shadcn.com/docs, coss.com/ui/docs, alignui.com,
daisyui.com/docs, heroui.com/en/docs, ant.design/docs/react, and each
GitHub repo's license field. Licenses rechecked 2026-11-15: HeroUI's LICENSE
file in heroui-inc/heroui (changed to Apache-2.0 in #6415, 2026-04-09);
AlignUI's free components in alignui/alignui-nextjs-typescript-starter
(components/ui, MIT).
