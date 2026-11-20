# The harness route (Next.js App Router)

Three files. The point of all three is the same: render the real components
against fixed props, with nothing that needs a network, a session or a clock.

## `app/(dev)/layout.tsx`: a second root layout

Route groups may each have their own root layout, which is what lets the harness
skip the auth provider the app's own layout mounts. Keep the fonts and
`globals.css` so the type and theme match the real thing.

```tsx
import { Geist, Geist_Mono } from "next/font/google";
import "../globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const viewport = { width: "device-width", initialScale: 1 };

export default function DevLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}>
      <body suppressHydrationWarning className="h-full overflow-hidden bg-black text-white">
        {children}
      </body>
    </html>
  );
}
```

## `app/(dev)/ui-stress/page.tsx`: dev only, scene from the query

```tsx
import { notFound } from "next/navigation";
import { Stress } from "./Stress";

export default async function UiStressPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  if (process.env.NODE_ENV !== "development") notFound();
  const { scene } = await searchParams;
  return <Stress scene={typeof scene === "string" ? scene : "results"} />;
}
```

## `app/(dev)/ui-stress/Stress.tsx`: one scene per surface

Two things earn their keep here.

**A stub backend provider.** Components that call `useMutation` need a client in
context or they throw at render. Give them one that never connects, and an auth
hook that reports signed out: every query then stays `skip`, which is the same
`undefined` those components already render while a real one is in flight.

```tsx
const noAuth = () => ({
  isLoading: false,
  isAuthenticated: false,
  fetchAccessToken: async () => null,
});

const client = useMemo(() => new ConvexReactClient("https://harness.convex.cloud"), []);
// <ConvexProviderWithAuth client={client} useAuth={noAuth}>…
```

**A mount gate.** A dialog scene is open on its first render, and a portalled
modal does not exist on the server: guaranteed hydration mismatch. In the app
this never arises, because every dialog starts closed. Note `useSyncExternalStore`
rather than `useState` + `useEffect`: the latter trips `react-hooks/set-state-in-effect`.

```tsx
const mounted = useSyncExternalStore(() => () => {}, () => true, () => false);
if (!mounted) return null;
```

**Match the real container.** Copy the wrapper the surface actually lives in
(`px-4 sm:px-6` → `mx-auto w-full max-w-3xl`), or the widths you measure are not
the widths the app has.
