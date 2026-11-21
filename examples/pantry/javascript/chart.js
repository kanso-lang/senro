// Draws the shelf's counts as a bar chart with Chartist. The shelf's view
// marks an element `data-owned-by="chart"` and writes the names and counts
// into its `data-names` and `data-counts`. senro's morph leaves that
// element's children alone and keeps its attributes current, so this module
// draws a chart into each such element when it appears and draws it again
// when the counts change.
import { BarChart } from "chartist";

const charts = new WeakMap();

const data = (el) => ({
  labels: el.dataset.names ? el.dataset.names.split("\n") : [],
  series: [el.dataset.counts ? el.dataset.counts.split(" ").map(Number) : []],
});

const options = { axisY: { onlyInteger: true, low: 0 }, height: "10rem" };

const drawn = (el) => {
  const chart = charts.get(el);
  if (chart) chart.update(data(el));
  else charts.set(el, new BarChart(el, data(el), options));
};

const owned = (node) =>
  node.nodeType === Node.ELEMENT_NODE
    ? [...(node.matches("[data-owned-by=chart]") ? [node] : []),
       ...node.querySelectorAll("[data-owned-by=chart]")]
    : [];

new MutationObserver((changes) => {
  for (const c of changes) {
    if (c.type === "attributes") owned(c.target).forEach(drawn);
    else c.addedNodes.forEach((n) => owned(n).forEach(drawn));
  }
}).observe(document.body, {
  subtree: true,
  childList: true,
  attributes: true,
  attributeFilter: ["data-names", "data-counts"],
});

owned(document.body).forEach(drawn);
