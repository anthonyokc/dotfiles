import { resolve } from "node:path"
import { toMarkdown } from "@firecrawl/anydoc"
import type { Plugin } from "@opencode/plugin"

export default {
  id: "anydoc",
  async setup(ctx: Plugin.Context) {
    await ctx.tool.transform((editor) => {
      editor.add({
        name: "anydoc_convert",
        description:
          "Convert a Word, PowerPoint, Excel, OpenDocument, RTF, EPUB, CSV, or text-based PDF file to Markdown.",
        input: {
          type: "object",
          properties: {
            path: {
              type: "string",
              minLength: 1,
              description: "Absolute path or path relative to the current project",
            },
          },
          required: ["path"],
          additionalProperties: false,
        },
        async execute(input, context) {
          const { path } = input as { path: string }
          const session = await ctx.session.get({ sessionID: context.sessionID })
          return { content: await toMarkdown(resolve(session.location.directory, path)) }
        },
      })
    })
  },
} satisfies Plugin.Plugin
