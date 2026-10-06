import { expect, test } from "bun:test";
import { FileModels } from "../src/code-editor/fileModels";

type Model = { uri: string; content: string; disposed: boolean; dispose(): void };

function setUp(disk: Record<string, string>) {
  const models = new Map<string, Model>();
  let reads = 0;
  const create = (uri: string, content: string): Model => {
    const model: Model = {
      uri,
      content,
      disposed: false,
      dispose() {
        this.disposed = true;
        models.delete(uri);
      },
    };
    models.set(uri, model);
    return model;
  };
  const service = new FileModels<Model>({
    find: (uri) => models.get(uri),
    create,
    read: async (uri) => {
      reads += 1;
      return disk[uri];
    },
  });
  return { service, models, create, reads: () => reads };
}

const file = "file:///proj/b.go";

test("a file that is not open is read, and its model goes with the last reference", async () => {
  const { service, models, reads } = setUp({ [file]: "package b" });
  const [first, second] = await Promise.all([service.createModelReference(file), service.createModelReference(file)]);
  expect(reads()).toBe(1);
  expect(first.object.textEditorModel).toBe(second.object.textEditorModel);
  expect(first.object.textEditorModel.content).toBe("package b");
  first.dispose();
  first.dispose();
  expect(models.has(file)).toBe(true);
  second.dispose();
  expect(models.has(file)).toBe(false);
});

test("a file that cannot be read has no model", async () => {
  const { service } = setUp({});
  await expect(service.createModelReference(file)).rejects.toThrow("Model not found");
});

test("an open file's model is used as it is and survives its references", async () => {
  const { service, models, create, reads } = setUp({ [file]: "on disk" });
  const open = create(file, "unsaved");
  const reference = await service.createModelReference(file);
  expect(reads()).toBe(0);
  expect(reference.object.textEditorModel).toBe(open);
  reference.dispose();
  expect(models.has(file)).toBe(true);
});

test("a previewed file the page then opens is kept", async () => {
  const { service, models } = setUp({ [file]: "package b" });
  const reference = await service.createModelReference(file);
  service.keep(file);
  reference.dispose();
  expect(models.has(file)).toBe(true);
});

test("closing a file that is still previewed keeps its model until the preview ends", async () => {
  const { service, create } = setUp({});
  const open = create(file, "package b");
  const reference = await service.createModelReference(file);
  service.discard(file, open);
  expect(open.disposed).toBe(false);
  reference.dispose();
  expect(open.disposed).toBe(true);
});

test("closing a file nothing else shows drops its model at once", () => {
  const { service, create } = setUp({});
  const open = create(file, "package b");
  service.discard(file, open);
  expect(open.disposed).toBe(true);
});
