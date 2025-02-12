import md5 from "crypto-js/md5";
import sha256 from "crypto-js/sha256";
import encBase64 from "crypto-js/enc-base64";

export function isMacOS() {
  return /(Mac|iPhone|iPod|iPad)/i.test(navigator.platform);
}

export function isEditableElement(element) {
  return (
    element.matches && element.matches("input, textarea, [contenteditable]")
  );
}

export function isElementInViewport(element, proximity = 0) {
  const box = element.getBoundingClientRect();
  return box.bottom >= -proximity && box.top <= window.innerHeight + proximity;
}

export function isElementHidden(element) {
  return element.offsetParent === null;
}

export function waitUntilVisible(element) {
  let observer = null;

  return new Promise((resolve, reject) => {
    if (isElementHidden(element)) {
      observer = new ResizeObserver((entries) => {
        if (!isElementHidden(element)) {
          observer.disconnect();
          resolve();
        }
      });
      observer.observe(element);
    } else {
      resolve();
    }
  });
}

/**
 * Returns a promise that resolves when the element enters the viewport.
 *
 * ## Options
 *
 *   * `root` - a scrollable ancestor that should be used for observing
 *     the intersection, instead of the viewport
 *
 *   * `proximity` - the number of pixels around `root` used to expand
 *     the intersection box, which effectively resolves the promise when
 *     `element` is in certain proximity of the viewport. Note that if
 *     the element is inside a scrollable ancestor, the ancestor must
 *     be set as `root`.
 *
 *     > NOTE: rootMargin only applies to the intersection root itself.
 *     > If a target Element is clipped by an ancestor other than the
 *     > intersection root, that clipping is unaffected by rootMargin.
 *     > ~ https://w3c.github.io/IntersectionObserver
 *
 */
export function waitUntilInViewport(
  element,
  { root = null, proximity = 0 } = {},
) {
  let observer = null;

  const promise = new Promise((resolve, reject) => {
    if (isElementVisibleInViewport(element, proximity)) {
      resolve();
    } else {
      observer = new IntersectionObserver(
        (entries) => {
          if (entries[0].isIntersecting) {
            observer.disconnect();
            observer = null;
            resolve();
          }
        },
        { root, rootMargin: `${proximity}px` },
      );
      observer.observe(element);
    }
  });

  const cancel = () => {
    observer && observer.disconnect();
  };

  return { promise, cancel };
}

export function isElementVisibleInViewport(element, proximity = 0) {
  return !isElementHidden(element) && isElementInViewport(element, proximity);
}

export function clamp(n, x, y) {
  return Math.min(Math.max(n, x), y);
}

export function getLineHeight(element) {
  const computedStyle = window.getComputedStyle(element);
  const lineHeight = parseInt(computedStyle.lineHeight, 10);

  if (Number.isNaN(lineHeight)) {
    const clone = element.cloneNode();
    clone.innerHTML = "<br>";
    element.appendChild(clone);
    const singleLineHeight = clone.clientHeight;
    clone.innerHTML = "<br><br>";
    const doubleLineHeight = clone.clientHeight;
    element.removeChild(clone);
    const lineHeight = doubleLineHeight - singleLineHeight;
    return lineHeight;
  } else {
    return lineHeight;
  }
}

export function selectElementContent(element) {
  const selection = window.getSelection();
  const range = document.createRange();
  range.selectNodeContents(element);
  selection.removeAllRanges();
  selection.addRange(range);
}

export function smoothlyScrollToElement(element) {
  const { height } = element.getBoundingClientRect();

  if (height < window.innerHeight) {
    element.scrollIntoView({ behavior: "smooth", block: "center" });
  } else {
    element.scrollIntoView({ behavior: "smooth", block: "start" });
  }
}

export function isScrolledToEnd(element) {
  // See https://developer.mozilla.org/en-US/docs/Web/API/Element/scrollHeight#determine_if_an_element_has_been_totally_scrolled
  return (
    Math.abs(element.scrollHeight - element.clientHeight - element.scrollTop) <
    1
  );
}

export function scrollToEnd(element) {
  element.scrollTop = element.scrollHeight;
}

/**
 * Transforms a UTF8 string into base64 encoding.
 */
export function encodeBase64(string) {
  return btoa(unescape(encodeURIComponent(string)));
}

/**
 * Transforms base64 encoding into UTF8 string.
 */
export function decodeBase64(binary) {
  return decodeURIComponent(escape(atob(binary)));
}

/**
 * Generates a random string.
 */
export function randomId() {
  return randomString(24);
}

/**
 * Generates a random long string.
 */
export function randomToken() {
  return randomString(40);
}

function randomString(byteSize) {
  const array = new Uint8Array(byteSize);
  crypto.getRandomValues(array);
  const byteString = String.fromCharCode(...array);
  return btoa(byteString);
}

/**
 * Calculates MD5 of the given string and returns
 * the base64 encoded binary.
 */
export function md5Base64(string) {
  return md5(string).toString(encBase64);
}

/**
 * Calculates SHA256 of the given string and returns
 * the base64 encoded binary.
 */
export function sha256Base64(string) {
  return sha256(string).toString(encBase64);
}

/**
 * A simple throttle version that ensures
 * the given function is called at most once
 * within the given time window.
 */
export function throttle(fn, windowMs) {
  let ignore = false;

  return (...args) => {
    if (!ignore) {
      fn(...args);
      ignore = true;
      setTimeout(() => {
        ignore = false;
      }, windowMs);
    }
  };
}

export function setFavicon(name) {
  let link = document.querySelector(`[rel="icon"]`);

  if (!link) {
    link = document.createElement("link");
    link.rel = "icon";
    document.head.appendChild(link);
  }

  link.href = `/favicons/${name}.svg`;
}

export function findChildOrThrow(element, selector) {
  const child = element.querySelector(selector);

  if (!child) {
    throw new Error(
      `expected a child matching ${selector}, but none was found`,
    );
  }

  return child;
}

export function findClosestOrThrow(element, selector) {
  const closest = element.closest(selector);

  if (!closest) {
    throw new Error(
      `expected closest matching ${selector}, but none was found`,
    );
  }

  return closest;
}

export function cancelEvent(event) {
  // Cancel any default browser behavior.
  event.preventDefault();
  // Stop event propagation (e.g. so it doesn't reach the editor).
  event.stopPropagation();
}

const htmlEscapes = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39",
};

/**
 * Transforms the given string to a HTML-safe value.
 */
export function escapeHtml(string) {
  return (string || "").replace(/[&<>"']/g, (char) => htmlEscapes[char]);
}

/**
 * Encodes the given binary buffer into base64 string.
 */
export function bufferToBase64(buffer) {
  let binaryString = "";
  const bytes = new Uint8Array(buffer);
  const length = bytes.byteLength;

  for (let i = 0; i < length; i++) {
    binaryString += String.fromCharCode(bytes[i]);
  }

  return btoa(binaryString);
}

/**
 * Decodes a base64 string into a binary buffer.
 */
export function base64ToBuffer(base64) {
  const binaryString = atob(base64);
  const bytes = new Uint8Array(binaryString.length);
  const length = bytes.byteLength;

  for (let i = 0; i < length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }

  return bytes.buffer;
}

export function isFeatureFlagEnabled(feature) {
  const features = document
    .querySelector("body")
    .getAttribute("data-feature-flags", "");

  if (features.legnth === 0) {
    return false;
  } else {
    return features.split(",").includes(feature);
  }
}

export function cookieOptions() {
  if (document.body.hasAttribute("data-within-iframe")) {
    return ";SameSite=None;Secure";
  } else {
    return ";SameSite=Lax";
  }
}

/**
 * Removes `key` from `object` and returns the associated value and
 * the updated object.
 */
export function pop(object, key, defaultValue = undefined) {
  if (object.hasOwnProperty(key)) {
    const { [key]: value, ...newObject } = object;
    return [value, newObject];
  }

  return [defaultValue, object];
}

export function wait(milliseconds) {
  return new Promise((resolve, reject) => {
    setTimeout(() => resolve(), milliseconds);
  });
}

export function isSafari() {
  return /^((?!chrome|android).)*safari/i.test(navigator.userAgent);
}

/**
 * Alters element style with the given properties for the callback
 * execution.
 *
 * After the callback is executed, the initial style is restored.
 */
export function withStyle(element, style, callback) {
  const initialStyle = {};

  for (const key in style) {
    initialStyle[key] = element.style[key];
    element.style[key] = style[key];
  }

  callback();

  Object.assign(element.style, initialStyle);
}
