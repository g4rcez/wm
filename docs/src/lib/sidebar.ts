import { getCollection, type CollectionEntry } from "astro:content";

export type Doc = CollectionEntry<"docs">;

export const groups = ["Start", "Configure", "Layouts", "Features", "Reference", "Guides"] as const;

/** All doc pages in reading order: by group, then by `order`. */
export async function getDocs(): Promise<Doc[]> {
  const docs = await getCollection("docs");
  return docs.sort(
    (a, b) => groups.indexOf(a.data.group) - groups.indexOf(b.data.group) || a.data.order - b.data.order,
  );
}

export function groupDocs(docs: Doc[]) {
  return groups.map((name) => ({ name, items: docs.filter((d) => d.data.group === name) }));
}
