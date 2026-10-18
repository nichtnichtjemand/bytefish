from std.collections import Optional


struct Move(Copyable):
    var from_field: String
    var to_field: String
    var promotion: Optional[String]

    var from_column: Int
    var from_row: Int
    var to_column: Int
    var to_row: Int

    def __init__(
        out self,
        from_field: String,
        to_field: String,
        promotion: Optional[String] = None,
    ):
        self.from_field = from_field
        self.to_field = to_field
        self.promotion = promotion

        try:
            if from_field.byte_length() >= 2 and to_field.byte_length() >= 2:
                # Spaltenberechnung: ASCII-Wert des Buchstabens minus 97 ('a')
                self.from_column = Int(from_field.lower()[byte=0]) - 97
                # Reihenberechnung: 8 minus (ASCII-Wert der Zahl minus 48 ('0'))
                self.from_row = 8 - (Int(from_field[byte=1]) - 48)

                self.to_column = Int(to_field.lower()[byte=0]) - 97
                self.to_row = 8 - (Int(to_field[byte=1]) - 48)
            else:
                self.from_column = -1
                self.from_row = -1
                self.to_column = -1
                self.to_row = -1

    def __copyinit__(out self, other: Self):
        self.from_field = other.from_field
        self.to_field = other.to_field
        self.promotion = other.promotion
        self.from_column = other.from_column
        self.from_row = other.from_row
        self.to_column = other.to_column
        self.to_row = other.to_row
        except:
            # Falls ein Index-Fehler oder Parsing-Fehler auftritt
            self.from_column = -1
            self.from_row = -1
            self.to_column = -1
            self.to_row = -1

    def __str__(self) -> String:
        var promo_str = String("")
        if self.promotion:
            promo_str = " Promotion: " + self.promotion.value()
        return "From: " + self.from_field + " To: " + self.to_field + promo_str

    def __repr__(self) -> String:
        return self.__str__()
