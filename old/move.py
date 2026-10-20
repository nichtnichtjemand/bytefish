class Move:
    
    def __init__(self, from_field, to_field, promotion=None):
        self.from_field = from_field
        self.to_field = to_field

        try:
            self.from_column = ord(from_field[0].lower()) - ord("a")
            self.from_row = 8 - int(from_field[1])

            self.to_column = ord(to_field[0].lower()) - ord("a")
            self.to_row = 8 - int(to_field[1])
            self.promotion = promotion
        except (IndexError, ValueError, TypeError):
            self.from_column = -1
            self.from_row = -1
            self.to_column = -1
            self.to_row = -1

    def __str__(self) -> str:
        promotion = f" Promotion: {self.promotion}" if self.promotion else ""
        return f"From: {self.from_field} To: {self.to_field}{promotion}"

    def __repr__(self):
        return str(self)
    