class Move:
    
    def __init__(self, from_field, to_field):
        self.from_field = from_field
        self.to_field = to_field

        self.from_column = ord(from_field[0].lower()) - ord("a")
        self.from_row = 8 - int(from_field[1])

        # 3. Zielfeld in Zahlen umrechnen (0-7)
        self.to_column = ord(to_field[0].lower()) - ord("a")
        self.to_row = 8 - int(to_field[1])