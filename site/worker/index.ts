import handler from 'vinext/server/fetch-handler';

interface Env {
  ASSETS: Fetcher;
}

/**
 * The site's Worker. Static assets are served without it, except the films
 * under /demos/ (`run_worker_first` in wrangler.jsonc): the asset server
 * answers a Range request with the whole file and a 200, and Safari won't
 * play a video unless it gets 206 Partial Content.
 */
const worker = {
  async fetch(request: Request, env: Env, ctx: ExecutionContext) {
    if (new URL(request.url).pathname.startsWith('/demos/'))
      return serveWithRanges(request, env);
    return handler.fetch(request, env, ctx);
  },
};

export default worker;

async function serveWithRanges(request: Request, env: Env) {
  const asset = await env.ASSETS.fetch(request);
  if (asset.status !== 200) return asset;
  const headers = new Headers(asset.headers);
  headers.set('Accept-Ranges', 'bytes');
  // One range is all a media element asks for; anything else gets the whole file.
  const range = /^bytes=(\d*)-(\d*)$/.exec(request.headers.get('Range') ?? '');
  if (!range || (range[1] === '' && range[2] === '') || request.method !== 'GET')
    return new Response(asset.body, { status: 200, headers });

  const body = await asset.arrayBuffer();
  const size = body.byteLength;
  const [start, end] =
    range[1] === ''
      ? [Math.max(0, size - Number(range[2])), size - 1] // bytes=-N: the last N bytes
      : [Number(range[1]), Math.min(range[2] === '' ? size - 1 : Number(range[2]), size - 1)];
  if (start > end) {
    headers.set('Content-Range', `bytes */${size}`);
    headers.delete('Content-Length');
    return new Response(null, { status: 416, headers });
  }
  headers.set('Content-Range', `bytes ${start}-${end}/${size}`);
  headers.set('Content-Length', String(end - start + 1));
  return new Response(body.slice(start, end + 1), { status: 206, headers });
}
