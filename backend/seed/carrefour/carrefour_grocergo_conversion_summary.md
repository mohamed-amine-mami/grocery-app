# Carrefour → GrocerGo catalog conversion

Source: `/Users/medamine/projects/grocery-app/carrefour_food_500.csv`

|  |  |
| --- | --- |
| CSV rows | 500 |
| Converted products | 500 |
| Excluded | 0 |
| Duplicates removed | 0 |
| Unique brands | 142 |
| Brandless products | 119 |
| Valid photo URLs | 500 |
| Missing / invalid photos | 0 / 0 |
| Slug collisions | 1 |

## Categories

| GrocerGo category | Slug | Products |
| --- | --- | --- |
| Fruits | `fruits` | 4 |
| Légumes | `legumes` | 12 |
| Viandes et poissons | `viandes-poissons` | 32 |
| Produits laitiers | `produits-laitiers` | 50 |
| Boulangerie | `boulangerie` | 16 |
| Boissons | `boissons` | 26 |
| Fromages | `fromages` | 51 |
| Charcuterie et traiteur | `charcuterie-traiteur` | 12 |
| Surgelés | `surgeles` | 20 |
| Pâtes, riz et légumes secs | `pates-riz-legumes-secs` | 41 |
| Conserves et plats cuisinés | `conserves` | 23 |
| Thon et sardines | `thon-sardines` | 20 |
| Huiles | `huiles` | 16 |
| Sauces et condiments | `sauces-condiments` | 38 |
| Épices et olives | `epices-olives` | 8 |
| Fruits secs | `fruits-secs` | 8 |
| Snacks et apéritif | `snacks-aperitif` | 10 |
| Biscuits et gâteaux | `biscuits-gateaux` | 41 |
| Chocolat et confiserie | `chocolat-confiserie` | 22 |
| Petit déjeuner | `petit-dejeuner` | 18 |
| Café, thés et infusions | `cafe-the` | 19 |
| Sucre, farine et pâtisserie | `sucre-farine` | 13 |

Unmapped Carrefour categories: 0

## Sale units

| Unit | Products |
| --- | --- |
| PIECE | 414 |
| KG | 86 |
| L | 0 |

| Rule | Unit | Confidence | Products | Examples |
| --- | --- | --- | --- | --- |
| `loose-volume` | L | review | 0 |  |
| `market-produce` | KG | high | 16 | Ananas; Citron; Kiwi; Mangue; Basilic |
| `market-packed-vegetables` | KG | review | 4 | Champignon entier; Champignon slice petit; Oignon en barquette; Piments séchés |
| `market-butcher-poultry-fish` | KG | high | 30 | Tête d'agneau + 4 pattes; Beefteck de veau en barquete; Faux filet de veau; Jarret sans os; Pavé de veau |
| `market-smoked-fish` | KG | review | 2 | Saumon fumé de Norvège; Saumon fumé de Norvège |
| `market-nuts-olives` | KG | high | 8 | Amandes americaines; Graines de citrouille éclatées; Noisettes concassées; Noix de cajou; Olives noires |
| `market-spices-condiments` | KG | review | 8 | Citron salé; Cornichons extra fins; Câpres; Variantes; Graines de sésame doré |
| `market-deli` | KG | review | 5 | Mini salami de dinde dicky dicky; Jambon de dinde; Jambon de dinde campagne; Jambon de poulet; Salami de bœuf traditionnel |
| `cut-cheese` | KG | high | 10 | Fromage mozzarella; Fromage mozzarella 100 % lait; Fromage pour pizza cheese; Ricotta traditionnelle; Fromage rouge Edam |
| `counter-prepared` | KG | review | 3 | Chicken nuggets panés; Chicken nuggets frais; Cordon bleu frais |
| `bakery-and-deli-pieces` | PIECE | high | 20 | Pain à panini; Croissants nature; Mini viennoiserie; Gâteu au chocolat; Mille feuille |
| `packaged` | PIECE | high | 394 | Ice tea ananas; Coca Cola; FANTA orange; ORANGINA jaune; PUNCH orange |

Products with the slug of a development-catalog product (the importer would update them): 5 — see the JSON report.

Products to review: 25 (listed in the JSON report; they are in the catalog with the unit shown).

Price, stock, availability and quantity rules are not part of this catalog: the owner sets them on the store product.
