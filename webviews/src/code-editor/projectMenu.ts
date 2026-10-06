export type MenuItem = { label: string; run(): void };

let closeOpenMenu: (() => void) | undefined;

/**
 * Shows a menu at a point of the page. Picking an item runs it; a click
 * elsewhere, Escape or the window losing focus closes the menu.
 */
export function showMenu(parent: HTMLElement, x: number, y: number, items: MenuItem[]): void {
  closeOpenMenu?.();
  const menu = document.createElement("div");
  menu.className = "project-menu";
  const close = () => {
    menu.remove();
    window.removeEventListener("mousedown", closeOnOutsidePress, true);
    window.removeEventListener("keydown", closeOnEscape, true);
    window.removeEventListener("blur", close);
    closeOpenMenu = undefined;
  };
  const closeOnOutsidePress = (event: MouseEvent) => {
    if (!menu.contains(event.target as Node)) {
      close();
    }
  };
  const closeOnEscape = (event: KeyboardEvent) => {
    if (event.key === "Escape") {
      event.preventDefault();
      close();
    }
  };
  for (const item of items) {
    const row = document.createElement("div");
    row.className = "project-menu-item";
    row.textContent = item.label;
    row.addEventListener("click", () => {
      close();
      item.run();
    });
    menu.append(row);
  }
  parent.append(menu);
  const size = menu.getBoundingClientRect();
  menu.style.left = `${Math.max(4, Math.min(x, window.innerWidth - size.width - 4))}px`;
  menu.style.top = `${Math.max(4, Math.min(y, window.innerHeight - size.height - 4))}px`;
  window.addEventListener("mousedown", closeOnOutsidePress, true);
  window.addEventListener("keydown", closeOnEscape, true);
  window.addEventListener("blur", close);
  closeOpenMenu = close;
}
