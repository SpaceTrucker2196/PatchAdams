~ synthetic base line 1 ~
~ synthetic base line 2 ~
~ synthetic base line 3 ~
~ synthetic base line 4 ~
def validate(path: str) -> bool:
    with open(path, "rb") as f:
        head = f.read(4)
    return head == b"GLOW"


