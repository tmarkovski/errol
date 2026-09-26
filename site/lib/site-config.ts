/** Shared release links and metadata. Section copy lives with each component. */
export const siteConfig = {
  title: 'Errol — Let ChatGPT and Claude talk it out',
  description:
    'Errol is a free, open-source menu bar app that carries a conversation between the ChatGPT and Claude apps on your Mac. No API keys, no account, and no server in the middle.',
  /** Where the site lives; link previews and the canonical URL are built on it. */
  url: 'https://errol.chat',
  /** The link preview image, rendered from scripts/og/og.html. */
  image: {
    url: '/og.png',
    width: 1200,
    height: 630,
    alt: 'Errol. Let ChatGPT and Claude talk it out. A gold dot carries a reply along a loop from the ChatGPT app to the Claude app.',
  },
  repositoryUrl: 'https://github.com/tmarkovski/errol',
  /** The latest release's disk image, through the redirect in public/_redirects. */
  downloadUrl: 'https://errol.chat/download',
  minimumMacOS: '26.4',
} as const;
