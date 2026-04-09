import type { Metadata, Viewport } from "next";
import { Analytics } from "@vercel/analytics/react"
import "./globals.css";
import LayoutWrapper from "@/components/LayoutWrapper";
import { siteConfig } from "@/config/site";

export const metadata: Metadata = {
  title: {
    default: `${siteConfig.siteName} | Personal Music Streaming`,
    template: `%s | ${siteConfig.siteName}`
  },
  description:
    "Svara Web is a fast music streaming companion for search, playlists, albums, lyrics, queue control, and Jam invites powered by a shared API stack.",
  applicationName: siteConfig.appName,
  authors: [{ name: "Nishant", url: siteConfig.portfolioUrl }],
  generator: "Next.js",
  keywords: [
    "svara",
    "music streaming",
    "lyrics",
    "jam session",
    "jiosaavn api",
    "web music player",
    "queue control",
    "music discovery",
  ],
  referrer: "origin-when-cross-origin",
  creator: "Nishant",
  publisher: "Nishant",
  formatDetection: {
    email: false,
    address: false,
    telephone: false,
  },
  metadataBase: new URL(siteConfig.siteUrl), 
  alternates: {
    canonical: "/",
  },
  openGraph: {
    title: `${siteConfig.siteName} | Personal Music Streaming`,
    description:
      "Search, queue, lyrics, playlists, albums, and Jam invites in one Svara web experience.",
    url: siteConfig.siteUrl,
    siteName: siteConfig.siteName,
    images: [
      {
        url: "/assets/icons/logo.png", 
        width: 512,
        height: 512,
        alt: `${siteConfig.siteName} Logo`,
      },
    ],
    locale: "en_US",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: `${siteConfig.siteName} | Personal Music Streaming`,
    description:
      "Stream, search, and share Jam sessions with Svara Web.",
    creator: "@codewithevilxd", 
    images: ["/assets/icons/logo.png"],
  },
  icons: {
    icon: "/assets/icons/logo.png",
    shortcut: "/assets/icons/logo.png",
    apple: "/assets/icons/logo.png",
  },
  manifest: "/manifest.json", 
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-video-preview": -1,
      "max-image-preview": "large",
      "max-snippet": -1,
    },
  },
};

export const viewport: Viewport = {
  themeColor: "#1ed760",
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
      </head>
      <body suppressHydrationWarning className="antialiased selection:bg-primary selection:text-black">
        <LayoutWrapper>
          {children}
        </LayoutWrapper>
        <Analytics />
      </body>
    </html>
  );
}
