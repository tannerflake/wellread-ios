Yes, fallback logic is the right way to think about it.

The important thing is this: the Google Books API does not guarantee one cover image at one exact size. In the Volume resource, volumeInfo.imageLinks is just a set of whatever image sizes are available for that book, and the documented keys are smallThumbnail (~80 px), thumbnail (~128 px), small (~300 px), medium (~575 px), large (~800 px), and extraLarge (~1280 px). Those fields are sparse, so some books have only a couple of them, while others have more.  ￼

So if your app is always trying, say, imageLinks.large, then a decent chunk of books will “fail” simply because large is absent, even though medium or thumbnail exists. In other words, the usual fix is not “ask Google for a different resolution dynamically,” but “pick the best available size from the fields Google actually returned.”  ￼

I would think about the problem in two separate buckets:
	1.	The API response has no image field at the size you want
	2.	The API response has an image URL, but loading that URL fails in the client

Those need slightly different handling.

What the API is actually giving you

A typical volume can come back with something like:

{
  "volumeInfo": {
    "imageLinks": {
      "smallThumbnail": "...",
      "thumbnail": "...",
      "small": "...",
      "medium": "...",
      "large": "...",
      "extraLarge": "..."
    }
  }
}

But Google documents those as “available” image links, not guaranteed fields. So your selection logic should be ordered by preference and use the first non-empty value.  ￼

Best fallback strategy

Strategy 1: pick the best available URL from the API payload

This is the main thing you want.

If you want the biggest reasonable cover:

function getBestGoogleBooksCover(imageLinks) {
  if (!imageLinks) return null;

  return (
    imageLinks.extraLarge ||
    imageLinks.large ||
    imageLinks.medium ||
    imageLinks.small ||
    imageLinks.thumbnail ||
    imageLinks.smallThumbnail ||
    null
  );
}

If you want a smaller asset first for performance, reverse the order.

Strategy 2: if the chosen URL fails to load, try the next one

Even when a field exists, the actual image request can still fail in the real world because of network issues, hotlink weirdness, browser behavior, proxy/CDN behavior, or occasional bad upstream data. Google’s docs define the fields, but they do not promise every returned image URL will always render successfully in every client environment. The safe engineering approach is to treat image loading as fallible and use client-side fallback as well.  ￼

Example:

function getGoogleBooksCoverCandidates(imageLinks) {
  if (!imageLinks) return [];

  return [
    imageLinks.extraLarge,
    imageLinks.large,
    imageLinks.medium,
    imageLinks.small,
    imageLinks.thumbnail,
    imageLinks.smallThumbnail
  ].filter(Boolean);
}

Then in React:

import { useMemo, useState } from "react";

function BookCover({ imageLinks, title }) {
  const candidates = useMemo(
    () => getGoogleBooksCoverCandidates(imageLinks),
    [imageLinks]
  );

  const [index, setIndex] = useState(0);

  if (!candidates.length) {
    return <div>No cover available</div>;
  }

  return (
    <img
      src={candidates[index]}
      alt={`Cover for ${title}`}
      onError={() => {
        if (index < candidates.length - 1) {
          setIndex(index + 1);
        }
      }}
    />
  );
}

function getGoogleBooksCoverCandidates(imageLinks) {
  if (!imageLinks) return [];

  return [
    imageLinks.extraLarge,
    imageLinks.large,
    imageLinks.medium,
    imageLinks.small,
    imageLinks.thumbnail,
    imageLinks.smallThumbnail
  ].filter(Boolean);
}

That gives you both levels of fallback:
	•	missing key fallback
	•	broken image URL fallback

Can you request a specific resolution?

Not really in the clean, documented Books API sense.

The official Books API contract is the named imageLinks fields. The documentation describes those fields and their approximate widths, but it does not document an API parameter where you ask for arbitrary cover sizes like “give me 640 px instead of 575 px.”  ￼

You may notice returned image URLs sometimes include query params like zoom, edge, or related values. I would not build core logic around manually editing those unless you’ve tested it heavily and are comfortable treating it as unofficial behavior. The stable, documented path is: use the sizes Google explicitly returns in imageLinks.  ￼

My actual recommendation

I’d implement this exact policy:
	1.	Read volumeInfo.imageLinks
	2.	Build an ordered candidate list:
	•	extraLarge
	•	large
	•	medium
	•	small
	•	thumbnail
	•	smallThumbnail
	3.	Use the first one that exists
	4.	Attach an image onerror fallback that tries the next candidate
	5.	If all fail, show a local placeholder cover

That’s the robust version.

A subtle but common mistake

A lot of apps accidentally do this:

const src = book.volumeInfo?.imageLinks?.thumbnail;

and stop there.

That’s fine if your UI only wants a small image, but it’s a mistake if:
	•	you wanted a larger image and assumed thumbnail would upscale well
	•	you wanted any image and didn’t check the other sizes
	•	you assumed thumbnail would always exist

You should usually centralize the logic in one helper so every surface in your app behaves consistently.

Recommended helper

export function resolveGoogleBooksCover(imageLinks) {
  const candidates = [
    imageLinks?.extraLarge,
    imageLinks?.large,
    imageLinks?.medium,
    imageLinks?.small,
    imageLinks?.thumbnail,
    imageLinks?.smallThumbnail
  ].filter(Boolean);

  return {
    primary: candidates[0] || null,
    fallbacks: candidates.slice(1)
  };
}

Or even:

export function getGoogleBooksCoverCandidates(imageLinks, preferred = "large") {
  const orders = {
    large: ["extraLarge", "large", "medium", "small", "thumbnail", "smallThumbnail"],
    medium: ["medium", "large", "small", "thumbnail", "extraLarge", "smallThumbnail"],
    thumb: ["thumbnail", "smallThumbnail", "small", "medium", "large", "extraLarge"]
  };

  const order = orders[preferred] || orders.large;

  return order
    .map((key) => imageLinks?.[key])
    .filter(Boolean);
}

That lets different UI surfaces choose different strategies.

One more thing worth checking

If by “failing” you mean you sometimes get no cover data at all, that can simply be because Google doesn’t have a cover exposed for that specific volume. The API only returns the image links that are available for that record.  ￼

If by “failing” you mean the URL exists but the browser still shows a broken image, then fallback-on-error is the right second layer.

So the objective answer is:
	•	Yes, you should absolutely implement fallback logic.
	•	No, the normal solution is not “request progressively lower custom resolutions.”
	•	The right solution is “walk the documented imageLinks sizes in priority order, then fall back again if the chosen URL fails to render.”  ￼

If you want, paste one real Google Books API response that’s giving you trouble and I’ll show you exactly how I’d write the resolver for your stack.