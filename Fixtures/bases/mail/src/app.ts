~ synthetic base line 1 ~
~ synthetic base line 2 ~
~ synthetic base line 3 ~
  zoom: number
}

export function key(t: Tile): string {
  return `${t.zoom}/${t.x}/${t.y}`
}
