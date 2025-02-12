import HyperList from "hyperlist";
import { parseHookProps } from "../lib/attribute";
import {
  findChildOrThrow,
  findClosestOrThrow,
  getLineHeight,
  isScrolledToEnd,
  scrollToEnd,
} from "../lib/utils";

/**
 * A hook used to render text lines as a virtual list, so that only
 * the visible lines are actually in the DOM.
 *
 * ## Props
 *
 *   * `max-height` - the maximum height of the element, exceeding
 *     this height enables scrolling
 *
 *   * `max-height-amplified` - the maximum height of the element
 *      when "Amplify Output" is selected in the UI, exceeding this
 *      height enables scrolling when selected
 *
 *   * `follow` - whether to automatically scroll to the bottom as
 *     new lines appear
 *
 *   * `max-lines` - the maximum number of lines to keep in the DOM.
 *     By default all lines are kept
 *
 *   * `ignore-trailing-empty-line` - whether to ignore the last
 *     line if it is empty
 *
 * ## Children
 *
 *   * `[data-template]` - a hidden container containing all the line
 *     elements, each with a data-line attribute
 *
 *   * `[data-content]` - the target element to render the virtualized
 *     lines into, it should contain the styling relevant text styles
 */
const VirtualizedLines = {
  mounted() {
    this.props = this.getProps();

    this.lineHeight = getLineHeight(this.el);
    this.templateEl = findChildOrThrow(this.el, "[data-template]");
    this.contentEl = findChildOrThrow(this.el, "[data-content]");
    this.cellEl = findClosestOrThrow(this.el, "[data-el-cell]");
    this.amplifyOutput = this.isAmplifyOutput();
    this.amplifyObserver = this.newAmplifyObserver();

    this.capLines();

    const config = this.hyperListConfig();
    this.virtualizedList = new HyperList(this.contentEl, config);

    if (this.props.follow) {
      scrollToEnd(this.contentEl);
    }
  },

  updated() {
    this.props = this.getProps();

    this.capLines();

    const shouldScrollToEnd =
      this.props.follow && isScrolledToEnd(this.contentEl);

    const config = this.hyperListConfig();
    this.virtualizedList.refresh(this.contentEl, config);

    if (shouldScrollToEnd) {
      scrollToEnd(this.contentEl);
    }
  },

  destroyed() {
    this.amplifyObserver.disconnect();
  },

  getProps() {
    return parseHookProps(this.el, [
      "max-height",
      "max-height-amplified",
      "follow",
      "max-lines",
      "ignore-trailing-empty-line",
    ]);
  },

  hyperListConfig() {
    const lineEls = this.getLineElements();
    const numberOfLines = lineEls.length;

    const height = Math.min(
      this.amplifyOutput ? this.props.maxHeightAmplified : this.props.maxHeight,
      this.lineHeight * numberOfLines,
    );

    return {
      height,
      total: numberOfLines,
      itemHeight: this.lineHeight,
      generate: (index) => {
        const node = lineEls[index].cloneNode(true);
        node.removeAttribute("id");
        return node;
      },
      afterRender: () => {
        // The content element has a fixed height and when the horizontal
        // scrollbar appears, it's treated as part of the element's content.
        // To accommodate for the scrollbar we dynamically add more height
        // to the element.
        if (this.contentEl.scrollWidth > this.contentEl.clientWidth) {
          this.contentEl.style.height = `${height + 12}px`;
        } else {
          this.contentEl.style.height = `${height}px`;
        }
      },
    };
  },

  getLineElements() {
    const lineEls = Array.from(this.templateEl.querySelectorAll("[data-line]"));

    if (lineEls.length === 0) {
      return [];
    }

    const lastLineEl = lineEls[lineEls.length - 1];

    if (this.props.ignoreTrailingEmptyLine && lastLineEl.innerText === "") {
      return lineEls.slice(0, -1);
    } else {
      return lineEls;
    }
  },

  capLines() {
    if (this.props.maxLines) {
      const lineEls = Array.from(
        this.templateEl.querySelectorAll("[data-line]"),
      );
      const ignoredLineEls = lineEls.slice(0, -this.props.maxLines);

      const [first, ...rest] = ignoredLineEls;
      rest.forEach((lineEl) => lineEl.remove());

      if (first) {
        first.innerHTML = "...";
      }
    }
  },

  newAmplifyObserver() {
    const observer = new MutationObserver((mutationRecords) => {
      if (
        mutationRecords.length != 1 ||
          mutationRecords[0].target != this.cellEl ||
          mutationRecords[0].attributeName != "data-js-amplified"
      ) { throw new Error("unexpected mutation changing Amplify Output"); }

      this.amplifyOutput = this.isAmplifyOutput();
      this.updated();
    });
    observer.observe(this.cellEl, {attributeFilter: ["data-js-amplified"]});
    return observer;
  },

  isAmplifyOutput() {
    return (this.cellEl.getAttribute("data-js-amplified") != null);
  },
};

export default VirtualizedLines;
