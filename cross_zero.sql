CREATE TABLE gameboard (
    id serial primary key,
    a char,
    b char,
    c char
);

insert into gameboard (id) values  (1), (2), (3);

CREATE TABLE game_state (
    label text,
    game_over boolean,
    gamer_misprint boolean,
    modified_by_code boolean
);

INSERT INTO game_state (label) VALUES ('cell');

CREATE OR REPLACE FUNCTION get_content_from_gameboard(gameboard_cell INTEGER)
RETURNS char AS $gcfg$
DECLARE
	placing_zero_cell INTEGER;
	i INTEGER;
	j INTEGER;
	gameboard_column CHAR[3];
	result CHAR;
BEGIN
	gameboard_column[1] = 'a';
	gameboard_column[2] = 'b';
	gameboard_column[3] = 'c';
	i := (gameboard_cell - 1) % 3 + 1;
	j := (gameboard_cell - 1) / 3 + 1;
  EXECUTE format('SELECT %I FROM gameboard WHERE id = $1', gameboard_column[j]) INTO result USING i;
  RETURN result;
END
$gcfg$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION place_zero_on_gameboard(gameboard_cell INTEGER)
RETURNS VOID AS $pz$
DECLARE
	i INTEGER;
	j INTEGER;
	gameboard_column CHAR[3];
BEGIN
	gameboard_column[1] = 'a';
	gameboard_column[2] = 'b';
	gameboard_column[3] = 'c';
	i := (gameboard_cell - 1) % 3 + 1;
	j := (gameboard_cell - 1) / 3 + 1;
  EXECUTE format('UPDATE gameboard SET %I = $1 WHERE id = $2', gameboard_column[j]) USING 'O', i;
  RETURN;
END
$pz$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION retaliatory_move ()
RETURNS VOID AS $rm$
DECLARE
	placing_zero_cell INTEGER;
	empty_cell_index INTEGER;
	i INTEGER;
	j INTEGER;
	triplet INTEGER[3];
	profitable_positions_order INTEGER[9][2]=ARRAY[
		[0, 0],
		[0, 0],
		[0, 0],
		[0, 0],
		[0, 0],
		[0, 0],
		[0, 0],
		[0, 0],
		[0, 0]
	];
	triplets INTEGER[8][3]=ARRAY[
		[1, 4, 7],
		[2, 5, 8],
		[3, 6, 9],
		[1, 2, 3],
		[4, 5, 6],
		[7, 8, 9],
		[3, 5, 7],
		[1, 5, 9]
	];
-- Поля строки массива:
-- 1. "Перспективность" построения тройки
--      если в триплете есть и 'X' и 'O',
--      то триплет бесперспективный и отмечается 0
-- 2. Наличие символов 'X' (для перспективных).
-- 3. Наличие символов 'O' (для перспективных).
-- 4. Номер незаполненной ячейки, если есть два 'X'.
--			(если есть два 'O' и пропуск то эта
-- 				ситуация не требует дальнейшего анализа
--				и отрабатывается простым победным ходом)
	promising_triplets INTEGER[8][4]=ARRAY[
		[1, 0, 0, 0],
		[1, 0, 0, 0],
		[1, 0, 0, 0],
		[1, 0, 0, 0],
		[1, 0, 0, 0],
		[1, 0, 0, 0],
		[1, 0, 0, 0],
		[1, 0, 0, 0]
	];
	content CHAR;
	count_O INTEGER;
	count_X INTEGER;
	is_changed BOOLEAN;
	pocket INTEGER[2];
BEGIN
	FOR i IN 1..8 LOOP
		count_O := 0;
		count_X := 0;
		empty_cell_index := 0;
		FOR j IN 1..3 LOOP
			content := get_content_from_gameboard(triplets[i][j]);
			CASE content
				WHEN 'X' THEN
					count_X := count_X + 1;
				WHEN 'O' THEN
					count_O := count_O + 1;
				ELSE
					empty_cell_index := triplets[i][j];
			END CASE;
		END LOOP;
		IF count_O = 2 AND empty_cell_index <> 0 THEN
-- Победный ход
			PERFORM place_zero_on_gameboard(empty_cell_index);
			UPDATE game_state SET game_over = true WHERE label = 'cell';
			RETURN;
		ELSIF count_X = 2 AND empty_cell_index <> 0 THEN
			promising_triplets[i][4] := empty_cell_index;
		ELSIF count_X > 0 AND count_O > 0 THEN
			promising_triplets[i][1] := 0;
		ELSE
			promising_triplets[i][2] := count_X;
			promising_triplets[i][3] := count_O;
		END IF;
	END LOOP;

	FOR i IN 1..9 LOOP
		profitable_positions_order[i][1] := i;
	END LOOP;

	FOR i IN 1..8 LOOP
		IF promising_triplets[i][4] <> 0 THEN
-- Не даём сделать победный ход сопернику
			PERFORM place_zero_on_gameboard(promising_triplets[i][4]);
			RETURN;
		END IF;
-- Строим рейтинг ячеек. Чем больше у ячейки вхождений в перспективные триплеты,
-- тем выше рейтинг.
		IF promising_triplets[i][1] <> 0 THEN
			FOR j IN 1..3 LOOP
				CASE triplets[i][j]
					WHEN 1 THEN
					  profitable_positions_order[1][2] := profitable_positions_order[1][2] + 1;
					WHEN 2 THEN
					  profitable_positions_order[2][2] := profitable_positions_order[2][2] + 1;
					WHEN 3 THEN
					  profitable_positions_order[3][2] := profitable_positions_order[3][2] + 1;
					WHEN 4 THEN
					  profitable_positions_order[4][2] := profitable_positions_order[4][2] + 1;
					WHEN 5 THEN
					  profitable_positions_order[5][2] := profitable_positions_order[5][2] + 1;
					WHEN 6 THEN
					  profitable_positions_order[6][2] := profitable_positions_order[6][2] + 1;
					WHEN 7 THEN
					  profitable_positions_order[7][2] := profitable_positions_order[7][2] + 1;
					WHEN 8 THEN
					  profitable_positions_order[8][2] := profitable_positions_order[8][2] + 1;
					WHEN 9 THEN
					  profitable_positions_order[9][2] := profitable_positions_order[9][2] + 1;
				END CASE;
			END LOOP;
		END IF;
	END LOOP;
-- Делаем сортировку по количеству вхождений ячейки в перспективные триплеты.
	LOOP
		is_changed = false;
		FOR i IN 1..8 LOOP
			IF profitable_positions_order[i][2] < profitable_positions_order[i+1][2] THEN
				pocket[1] := profitable_positions_order[i][1];
				pocket[2] := profitable_positions_order[i][2];
				profitable_positions_order[i][1] := profitable_positions_order[i+1][1];
				profitable_positions_order[i][2] := profitable_positions_order[i+1][2];
				profitable_positions_order[i+1][1] := pocket[1];
				profitable_positions_order[i+1][2] := pocket[2];
				is_changed := true;
			END IF;
		END LOOP;
		EXIT WHEN NOT is_changed;
	END LOOP;
-- Выбираем первую незанятую ячейку из перспективных.
	FOR i IN 1..9 LOOP
		placing_zero_cell = profitable_positions_order[i][1];
		content = get_content_from_gameboard(placing_zero_cell);
		IF (content) IS NULL THEN
			PERFORM place_zero_on_gameboard(placing_zero_cell);
			RETURN;
		END IF;
	END LOOP;
  RETURN;
END
$rm$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION after_game_move_handler()
RETURNS trigger AS $agmh$
DECLARE
	i INTEGER;
	foo BOOLEAN;
BEGIN
	IF EXISTS(SELECT game_over FROM game_state WHERE label = 'cell' AND game_over IS NOT NULL) THEN
		RETURN NULL;
	END IF;
  IF EXISTS(SELECT modified_by_code FROM game_state WHERE label = 'cell' AND modified_by_code IS NOT NULL) THEN
  	UPDATE game_state SET modified_by_code=NULL WHERE label = 'cell';
  	RETURN NULL;
  END IF;
  IF EXISTS(SELECT gamer_misprint FROM game_state WHERE label = 'cell' AND gamer_misprint IS NOT NULL) THEN
  	UPDATE game_state SET gamer_misprint=NULL WHERE label = 'cell';
  	RETURN NULL;
  END IF;
	UPDATE game_state SET modified_by_code=true WHERE label = 'cell';
	PERFORM retaliatory_move ();
	RETURN NULL;
END
$agmh$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION before_game_move_handler()
RETURNS trigger AS $$
DECLARE
	i INTEGER;
	n INTEGER;
	foo BOOLEAN;
BEGIN
	IF EXISTS(SELECT game_over FROM game_state WHERE label = 'cell' AND game_over IS NOT NULL) THEN
		RAISE NOTICE 'Game over!';
		RETURN OLD;
	END IF;
	IF EXISTS(SELECT modified_by_code FROM game_state WHERE label = 'cell' AND modified_by_code IS NOT NULL) THEN
		RETURN NEW;
	END IF;
	UPDATE game_state SET gamer_misprint=NULL WHERE label = 'cell';
	IF OLD.a IS NULL AND  NEW.a IS NOT NULL THEN
		IF NEW.a <> 'X' THEN
	UPDATE game_state SET gamer_misprint=true WHERE label = 'cell';
			RETURN OLD;
		END IF;
		i := 0;
	ELSIF OLD.b IS NULL AND  NEW.b IS NOT NULL THEN
		IF NEW.b <> 'X' THEN
	UPDATE game_state SET gamer_misprint=true WHERE label = 'cell';
			RETURN OLD;
		END IF;
		i := 3;
	ELSIF OLD.c IS NULL AND  NEW.c IS NOT NULL THEN
		IF NEW.c <> 'X' THEN
	UPDATE game_state SET gamer_misprint=true WHERE label = 'cell';
			RETURN OLD;
		END IF;
		i := 6;
	ELSE
		UPDATE game_state SET gamer_misprint=true WHERE label = 'cell';
		RETURN OLD;
	END IF;
	RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER after_game_step
AFTER UPDATE ON gameboard
FOR EACH ROW EXECUTE PROCEDURE after_game_move_handler();

CREATE TRIGGER before_game_step
BEFORE UPDATE ON gameboard
FOR EACH ROW EXECUTE PROCEDURE before_game_move_handler();
