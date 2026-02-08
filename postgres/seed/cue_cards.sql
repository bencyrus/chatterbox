-- 43 cues (created_at left empty), created_by = 1
insert into cues.cue (cue_id, created_by) values (1, 1);
insert into cues.cue (cue_id, created_by) values (2, 1);
insert into cues.cue (cue_id, created_by) values (3, 1);
insert into cues.cue (cue_id, created_by) values (4, 1);
insert into cues.cue (cue_id, created_by) values (5, 1);
insert into cues.cue (cue_id, created_by) values (6, 1);
insert into cues.cue (cue_id, created_by) values (7, 1);
insert into cues.cue (cue_id, created_by) values (8, 1);
insert into cues.cue (cue_id, created_by) values (9, 1);
insert into cues.cue (cue_id, created_by) values (10, 1);
insert into cues.cue (cue_id, created_by) values (11, 1);
insert into cues.cue (cue_id, created_by) values (12, 1);
insert into cues.cue (cue_id, created_by) values (13, 1);
insert into cues.cue (cue_id, created_by) values (14, 1);
insert into cues.cue (cue_id, created_by) values (15, 1);
insert into cues.cue (cue_id, created_by) values (16, 1);
insert into cues.cue (cue_id, created_by) values (17, 1);
insert into cues.cue (cue_id, created_by) values (18, 1);
insert into cues.cue (cue_id, created_by) values (19, 1);
insert into cues.cue (cue_id, created_by) values (20, 1);
insert into cues.cue (cue_id, created_by) values (21, 1);
insert into cues.cue (cue_id, created_by) values (22, 1);
insert into cues.cue (cue_id, created_by) values (23, 1);
insert into cues.cue (cue_id, created_by) values (24, 1);
insert into cues.cue (cue_id, created_by) values (25, 1);
insert into cues.cue (cue_id, created_by) values (26, 1);
insert into cues.cue (cue_id, created_by) values (27, 1);
insert into cues.cue (cue_id, created_by) values (28, 1);
insert into cues.cue (cue_id, created_by) values (29, 1);
insert into cues.cue (cue_id, created_by) values (30, 1);
insert into cues.cue (cue_id, created_by) values (31, 1);
insert into cues.cue (cue_id, created_by) values (32, 1);
insert into cues.cue (cue_id, created_by) values (33, 1);
insert into cues.cue (cue_id, created_by) values (34, 1);
insert into cues.cue (cue_id, created_by) values (35, 1);
insert into cues.cue (cue_id, created_by) values (36, 1);
insert into cues.cue (cue_id, created_by) values (37, 1);
insert into cues.cue (cue_id, created_by) values (38, 1);
insert into cues.cue (cue_id, created_by) values (39, 1);
insert into cues.cue (cue_id, created_by) values (40, 1);
insert into cues.cue (cue_id, created_by) values (41, 1);
insert into cues.cue (cue_id, created_by) values (42, 1);
insert into cues.cue (cue_id, created_by) values (43, 1);

-- cue_content_id sequential from 1..129, 3 rows per cue (en, fr, de)
-- details is empty string, created_at uses default (now())

-- Cue 1
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (1, 1, 'What kind of social or community action would you like to take part in?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (2, 1, 'Quel est le type d’action solidaire que vous aimeriez faire ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (3, 1, 'An welcher Art von sozialem oder solidarischem Engagement würden Sie gerne teilnehmen?', '', 'de');

-- Cue 2
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (4, 2, 'Some people struggle to adapt to life in a foreign country. What do you think?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (5, 2, 'Les personnes n’arrivent pas à s’adapter dans un pays étranger. Que pensez-vous ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (6, 2, 'Manche Menschen haben Schwierigkeiten, sich in einem fremden Land anzupassen. Was denken Sie darüber?', '', 'de');

-- Cue 3
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (7, 3, 'There is no age limit for learning or studying. What do you think?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (8, 3, 'Il n’y a pas d’âge pour apprendre ou faire des études. Qu’en pensez-vous ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (9, 3, 'Zum Lernen oder Studieren ist man nie zu alt. Was denken Sie darüber?', '', 'de');

-- Cue 4
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (10, 4, 'Who should take care of older people: citizens or the government? What is your opinion on civic action?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (11, 4, 'Qui doit aider les personnes âgées, les citoyens ou l’État ? Que pensez-vous de l’action civile ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (12, 4, 'Wer sollte ältere Menschen unterstützen: die Bürger oder der Staat? Wie stehen Sie zu zivilgesellschaftlichem Engagement?', '', 'de');

-- Cue 5
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (13, 5, 'Do you agree that older people are more pessimistic than younger ones? Are you optimistic about future generations?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (14, 5, 'Êtes-vous d’accord avec l’idée que les personnes âgées sont plus pessimistes que les jeunes ? Êtes-vous optimiste quant aux nouvelles générations ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (15, 5, 'Sind ältere Menschen Ihrer Meinung nach pessimistischer als junge? Sind Sie optimistisch in Bezug auf die jüngeren Generationen?', '', 'de');

-- Cue 6
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (16, 6, 'Is it possible to be friends with someone who has completely different beliefs from yours?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (17, 6, 'Est-il possible d’être ami avec quelqu’un qui a des convictions opposées aux vôtres ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (18, 6, 'Ist es möglich, mit jemandem befreundet zu sein, der ganz andere Überzeugungen hat als man selbst?', '', 'de');

-- Cue 7
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (19, 7, 'Is it easy to make new friends in a host country?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (20, 7, 'Est-il facile de se faire de nouveaux amis dans un pays d’accueil ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (21, 7, 'Ist es leicht, im Gastland neue Freunde zu finden?', '', 'de');

-- Cue 8
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (22, 8, 'Traveling makes you a better person. What do you think?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (23, 8, 'Voyager fait de vous une meilleure personne. Qu’en pensez-vous ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (24, 8, 'Reisen macht einen zu einem besseren Menschen. Was denken Sie darüber?', '', 'de');

-- Cue 9
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (25, 9, 'Vegetarian menus: are you for or against them?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (26, 9, 'Menus végétariens : êtes-vous pour ou contre ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (27, 9, 'Vegetarische Menüs – sind Sie dafür oder dagegen?', '', 'de');

-- Cue 10
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (28, 10, 'Weight loss advice in magazines: do you find it helpful or not?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (29, 10, 'Perdre du poids : les conseils des magazines sont-ils utiles ? Êtes-vous pour ou contre ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (30, 10, 'Abnehm-Tipps in Zeitschriften: Finden Sie sie hilfreich oder nicht?', '', 'de');

-- Cue 11
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (31, 11, 'Public transportation in cities should be free. Do you think this is a good idea?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (32, 11, 'Les transports en commun doivent être gratuits en ville. Est-ce une bonne idée selon vous ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (33, 11, 'Der öffentliche Nahverkehr in Städten sollte kostenlos sein. Halten Sie das für eine gute Idee?', '', 'de');

-- Cue 12
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (34, 12, 'To truly enjoy life, should we work less? What do you think?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (35, 12, 'Pour profiter de la vie, faut-il travailler moins ? Qu’en pensez-vous ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (36, 12, 'Muss man weniger arbeiten, um das Leben wirklich zu genießen? Was meinen Sie?', '', 'de');

-- Cue 13
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (37, 13, 'Should children be given a mobile phone?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (38, 13, 'Faut-il donner un téléphone aux enfants ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (39, 13, 'Sollten Kinder ein eigenes Handy bekommen?', '', 'de');

-- Cue 14
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (40, 14, 'Do you prefer living in a city or in the countryside? Why?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (41, 14, 'Préférez-vous vivre en ville ou à la campagne ? Pourquoi ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (42, 14, 'Leben Sie lieber in der Stadt oder auf dem Land? Warum?', '', 'de');

-- Cue 15
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (43, 15, 'Travel is an activity only for wealthy people. Do you agree?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (44, 15, 'Le voyage est une activité réservée aux personnes riches. Êtes-vous d’accord ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (45, 15, 'Reisen ist nur etwas für reiche Menschen. Stimmen Sie dem zu?', '', 'de');

-- Cue 16
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (46, 16, 'Everyone can reduce their waste. What do you think?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (47, 16, 'Tout le monde peut réduire ses déchets. Qu’en pensez-vous ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (48, 16, 'Jeder kann seinen Müll reduzieren. Was denken Sie darüber?', '', 'de');

-- Cue 17
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (49, 17, 'Are artistic professions real jobs? What is your opinion?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (50, 17, 'Les métiers artistiques sont-ils de vrais métiers ? Qu’en pensez-vous ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (51, 17, 'Sind künstlerische Berufe richtige Berufe? Was ist Ihre Meinung?', '', 'de');

-- Cue 18
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (52, 18, 'Do older people always give good advice?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (53, 18, 'Les personnes âgées donnent-elles toujours de bons conseils ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (54, 18, 'Geben ältere Menschen immer gute Ratschläge?', '', 'de');

-- Cue 19
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (55, 19, 'Do social networks make it easier to make new friends?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (56, 19, 'Les réseaux sociaux facilitent-ils les rencontres amicales ? Qu’en pensez-vous ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (57, 19, 'Erleichtern soziale Netzwerke das Knüpfen neuer Freundschaften?', '', 'de');

-- Cue 20
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (58, 20, 'Immigrating to Canada: what do you think about it?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (59, 20, 'Immigrer au Canada : qu’en pensez-vous ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (60, 20, 'Nach Kanada auswandern – was halten Sie davon?', '', 'de');

-- Cue 21
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (61, 21, 'Games of chance and gambling: what is your opinion?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (62, 21, 'Les jeux du hasard : qu’en pensez-vous ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (63, 21, 'Glücksspiele: Was halten Sie davon?', '', 'de');

-- Cue 22
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (64, 22, 'Do older people need to have a pet?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (65, 22, 'Les personnes âgées ont-elles besoin d’un animal de compagnie ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (66, 22, 'Brauchen ältere Menschen ein Haustier?', '', 'de');

-- Cue 23
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (67, 23, 'Using mobile phones at work: what do you think?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (68, 23, 'L’utilisation du téléphone portable au travail : qu’en pensez-vous ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (69, 23, 'Die Nutzung von Smartphones am Arbeitsplatz – was denken Sie darüber?', '', 'de');

-- Cue 24
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (70, 24, 'Should parents raise girls and boys in the same way?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (71, 24, 'Les parents doivent-ils éduquer filles et garçons de la même manière ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (72, 24, 'Sollten Eltern Mädchen und Jungen gleich erziehen?', '', 'de');

-- Cue 25
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (73, 25, 'Is the main role of school only to teach the academic curriculum?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (74, 25, 'La priorité de l’école est-elle uniquement d’enseigner le programme scolaire ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (75, 25, 'Besteht die Hauptaufgabe der Schule nur darin, den Lehrplan zu vermitteln?', '', 'de');

-- Cue 26
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (76, 26, 'Is reading essential to be cultured and to understand a country?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (77, 26, 'La lecture est-elle essentielle pour être cultivé et pour connaître un pays ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (78, 26, 'Ist Lesen notwendig, um gebildet zu sein und ein Land kennenzulernen?', '', 'de');

-- Cue 27
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (79, 27, 'When people leave their country to live elsewhere, is it always out of necessity?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (80, 27, 'Quand on quitte son pays pour vivre ailleurs, est-ce toujours par nécessité ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (81, 27, 'Wenn Menschen ihr Land verlassen, um woanders zu leben, geschieht das immer aus Notwendigkeit?', '', 'de');

-- Cue 28
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (82, 28, 'Should freedom of expression have limits?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (83, 28, 'La liberté d’expression a-t-elle des limites ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (84, 28, 'Sollte die Meinungsfreiheit Grenzen haben?', '', 'de');

-- Cue 29
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (85, 29, 'Can you really know a country without speaking its language?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (86, 29, 'Peut-on vraiment connaître un pays sans parler sa langue ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (87, 29, 'Kann man ein Land wirklich kennenlernen, ohne seine Sprache zu sprechen?', '', 'de');

-- Cue 30
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (88, 30, 'Do you need to earn a lot of money to enjoy life?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (89, 30, 'Faut-il gagner beaucoup d’argent pour profiter de la vie ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (90, 30, 'Muss man viel Geld verdienen, um das Leben zu genießen?', '', 'de');

-- Cue 31
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (91, 31, 'Has the internet changed behavior in the workplace?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (92, 31, 'Internet a-t-il changé les comportements au travail ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (93, 31, 'Hat das Internet das Verhalten am Arbeitsplatz verändert?', '', 'de');

-- Cue 32
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (94, 32, 'Which type of media do you prefer for getting information, and why?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (95, 32, 'Quel média préférez-vous pour vous informer et pourquoi ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (96, 32, 'Welches Medium bevorzugen Sie, um sich zu informieren, und warum?', '', 'de');

-- Cue 33
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (97, 33, 'To live well in a foreign country, is it necessary to build relationships with locals?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (98, 33, 'Pour bien vivre dans un pays étranger, faut-il créer des relations avec les habitants ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (99, 33, 'Ist es notwendig, Beziehungen zu Einheimischen aufzubauen, um sich in einem fremden Land wohlzufühlen?', '', 'de');

-- Cue 34
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (100, 34, 'When living abroad, should parents speak to their children in the host country’s language or their native language?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (101, 34, 'À l’étranger, faut-il parler aux enfants la langue du pays d’accueil ou celle d’origine ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (102, 34, 'Sollte man mit Kindern im Ausland die Sprache des Gastlandes oder die Muttersprache sprechen?', '', 'de');

-- Cue 35
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (103, 35, 'Is it possible to develop the economy while protecting the environment?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (104, 35, 'Peut-on développer l’économie tout en protégeant l’environnement ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (105, 35, 'Ist es möglich, die Wirtschaft zu entwickeln und gleichzeitig die Umwelt zu schützen?', '', 'de');

-- Cue 36
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (106, 36, 'Should people preserve their traditions and culture in a host country?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (107, 36, 'Faut-il préserver ses traditions et sa culture dans un pays d’accueil ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (108, 36, 'Sollte man im Gastland seine Traditionen und Kultur bewahren?', '', 'de');

-- Cue 37
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (109, 37, 'Is giving children money for good grades a good idea?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (110, 37, 'Donner de l’argent aux enfants pour de bonnes notes est-il une bonne idée ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (111, 37, 'Ist es eine gute Idee, Kindern Geld für gute Noten zu geben?', '', 'de');

-- Cue 38
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (112, 38, 'Is well-being at work really important?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (113, 38, 'Le bien-être au travail est-il vraiment important ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (114, 38, 'Ist Wohlbefinden am Arbeitsplatz wirklich wichtig?', '', 'de');

-- Cue 39
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (115, 39, 'Do professional athletes deserve their high salaries?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (116, 39, 'Les sportifs méritent-ils leurs salaires élevés ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (117, 39, 'Verdienen Profisportler ihre hohen Gehälter?', '', 'de');

-- Cue 40
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (118, 40, 'Is television gradually disappearing?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (119, 40, 'La télévision est-elle en train de disparaître ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (120, 40, 'Verschwindet das Fernsehen allmählich?', '', 'de');

-- Cue 41
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (121, 41, 'Do children spend too much time in front of screens?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (122, 41, 'Les enfants passent-ils trop de temps devant les écrans ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (123, 41, 'Verbringen Kinder zu viel Zeit vor Bildschirmen?', '', 'de');

-- Cue 42
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (124, 42, 'Is it easy to find a job abroad?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (125, 42, 'Est-il facile de trouver un emploi à l’étranger ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (126, 42, 'Ist es leicht, im Ausland einen Job zu finden?', '', 'de');

-- Cue 43
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (127, 43, 'Should people change their habits when living in a host country?', '', 'en');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (128, 43, 'Doit-on changer ses habitudes dans un pays d’accueil ?', '', 'fr');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (129, 43, 'Sollte man seine Gewohnheiten in einem Gastland ändern?', '', 'de');

insert into cues.cue_stage (cue_id, stage, created_by) values (1, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (2, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (3, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (4, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (5, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (6, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (7, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (8, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (9, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (10, 'published', 1);

insert into cues.cue_stage (cue_id, stage, created_by) values (11, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (12, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (13, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (14, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (15, 'published', 1);

insert into cues.cue_stage (cue_id, stage, created_by) values (16, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (17, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (18, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (19, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (20, 'published', 1);

insert into cues.cue_stage (cue_id, stage, created_by) values (21, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (22, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (23, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (24, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (25, 'published', 1);

insert into cues.cue_stage (cue_id, stage, created_by) values (26, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (27, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (28, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (29, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (30, 'published', 1);

insert into cues.cue_stage (cue_id, stage, created_by) values (31, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (32, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (33, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (34, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (35, 'published', 1);

insert into cues.cue_stage (cue_id, stage, created_by) values (36, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (37, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (38, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (39, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (40, 'published', 1);

insert into cues.cue_stage (cue_id, stage, created_by) values (41, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (42, 'published', 1);
insert into cues.cue_stage (cue_id, stage, created_by) values (43, 'published', 1);

-- Mandarin (zh) cue content
-- cue_content_id 130..172
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (130, 1, '你想参与哪种社会或社区公益活动？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (131, 2, '有些人很难适应在外国生活。你怎么看？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (132, 3, '学习或接受教育有没有年龄限制？你怎么看？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (133, 4, '照顾老年人应该由个人还是政府负责？你怎么看公民责任？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (134, 5, '你同意老年人比年轻人更悲观吗？你对未来的一代乐观吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (135, 6, '你觉得可以和价值观完全不同的人做朋友吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (136, 7, '在一个新的国家交朋友容易吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (137, 8, '旅行会让人成为更好的人吗？你怎么看？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (138, 9, '你支持还是反对素食菜单？为什么？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (139, 10, '杂志里的减肥建议有用吗？你怎么看？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (140, 11, '城市里的公共交通应该免费吗？你觉得这是个好主意吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (141, 12, '为了真正享受生活，我们应该少工作一些吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (142, 13, '你觉得应该给孩子手机吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (143, 14, '你更喜欢住在城市还是乡村？为什么？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (144, 15, '你同意旅行只属于有钱人吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (145, 16, '每个人都能减少垃圾吗？你怎么看？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (146, 17, '你认为艺术类职业算是真正的工作吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (147, 18, '老年人给的建议总是正确的吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (148, 19, '社交网络能让人更容易交到新朋友吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (149, 20, '你怎么看移民到加拿大这件事？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (150, 21, '你对赌博和博彩怎么看？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (151, 22, '老年人需要养宠物吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (152, 23, '在工作中使用手机合适吗？你怎么看？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (153, 24, '父母应该用同样的方式教育男孩和女孩吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (154, 25, '学校的主要作用只是教授课本知识吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (155, 26, '阅读对了解一个国家和提升文化素养重要吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (156, 27, '人们离开自己的国家生活在别处，是否总是出于迫不得已？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (157, 28, '言论自由应该有界限吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (158, 29, '不懂一国的语言，真的能了解这个国家吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (159, 30, '要过得开心，必须赚很多钱吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (160, 31, '互联网是否改变了人们在工作中的行为？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (161, 32, '你更喜欢通过哪种媒体获取信息？为什么？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (162, 33, '在外国生活，和当地人建立关系重要吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (163, 34, '生活在国外时，父母应该对孩子说当地语言还是母语？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (164, 35, '发展经济的同时保护环境是否可能？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (165, 36, '在国外生活时，是否应该保留自己的文化和传统？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (166, 37, '给孩子好成绩就给钱是个好主意吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (167, 38, '工作中的幸福感真的重要吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (168, 39, '你觉得职业运动员配得上他们的高薪吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (169, 40, '电视正在逐渐消失吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (170, 41, '孩子花在屏幕前的时间是不是太多了？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (171, 42, '在国外找工作容易吗？', '', 'zh');
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code) values (172, 43, '生活在一个新的国家时，人们应该改变自己的生活习惯吗？', '', 'zh');

-- Spanish (es) cue content
-- cue_content_id 173..215
insert into cues.cue_content (cue_content_id, cue_id, title, details, language_code)
values (173, 1, '¿En qué tipo de acción social o comunitaria te gustaría participar?', '', 'es');
insert into cues.cue_content values
(174, 2, 'A algunas personas les cuesta adaptarse a la vida en un país extranjero. ¿Qué opinas?', '', 'es');
insert into cues.cue_content values
(175, 3, 'No hay edad para aprender o estudiar. ¿Estás de acuerdo?', '', 'es');
insert into cues.cue_content values
(176, 4, '¿Quién debería cuidar a las personas mayores: los ciudadanos o el Estado? ¿Qué opinas del compromiso cívico?', '', 'es');
insert into cues.cue_content values
(177, 5, '¿Crees que las personas mayores son más pesimistas que los jóvenes? ¿Eres optimista respecto a las nuevas generaciones?', '', 'es');
insert into cues.cue_content values
(178, 6, '¿Es posible ser amigo de alguien con creencias completamente distintas a las tuyas?', '', 'es');
insert into cues.cue_content values
(179, 7, '¿Es fácil hacer nuevos amigos en el país de acogida?', '', 'es');
insert into cues.cue_content values
(180, 8, 'Viajar te hace mejor persona. ¿Qué piensas?', '', 'es');
insert into cues.cue_content values
(181, 9, 'Menús vegetarianos: ¿estás a favor o en contra?', '', 'es');
insert into cues.cue_content values
(182, 10, 'Los consejos para adelgazar en las revistas: ¿te parecen útiles o no?', '', 'es');
insert into cues.cue_content values
(183, 11, 'El transporte público en las ciudades debería ser gratuito. ¿Te parece una buena idea?', '', 'es');
insert into cues.cue_content values
(184, 12, 'Para disfrutar de verdad la vida, ¿deberíamos trabajar menos? ¿Qué opinas?', '', 'es');
insert into cues.cue_content values
(185, 13, '¿Deberían los niños tener un teléfono móvil?', '', 'es');
insert into cues.cue_content values
(186, 14, '¿Prefieres vivir en la ciudad o en el campo? ¿Por qué?', '', 'es');
insert into cues.cue_content values
(187, 15, 'Viajar es una actividad reservada solo para la gente rica. ¿Estás de acuerdo?', '', 'es');
insert into cues.cue_content values
(188, 16, 'Todo el mundo puede reducir sus residuos. ¿Qué piensas?', '', 'es');
insert into cues.cue_content values
(189, 17, '¿Las profesiones artísticas son “trabajos de verdad”? ¿Cuál es tu opinión?', '', 'es');
insert into cues.cue_content values
(190, 18, '¿Las personas mayores dan siempre buenos consejos?', '', 'es');
insert into cues.cue_content values
(191, 19, '¿Las redes sociales facilitan hacer nuevos amigos?', '', 'es');
insert into cues.cue_content values
(192, 20, 'Emigrar a Canadá: ¿qué opinas al respecto?', '', 'es');
insert into cues.cue_content values
(193, 21, 'Juegos de azar y apuestas: ¿qué opinas?', '', 'es');
insert into cues.cue_content values
(194, 22, '¿Las personas mayores necesitan una mascota?', '', 'es');
insert into cues.cue_content values
(195, 23, 'Usar el móvil en el trabajo: ¿qué te parece?', '', 'es');
insert into cues.cue_content values
(196, 24, '¿Los padres deberían educar a niñas y niños de la misma manera?', '', 'es');
insert into cues.cue_content values
(197, 25, '¿El papel principal de la escuela es solo enseñar el programa académico?', '', 'es');
insert into cues.cue_content values
(198, 26, '¿Leer es esencial para tener cultura y comprender un país?', '', 'es');  
insert into cues.cue_content values
(199, 27, 'Cuando la gente deja su país para vivir en otro lugar, ¿siempre es por necesidad?', '', 'es');
insert into cues.cue_content values
(200, 28, '¿La libertad de expresión debería tener límites?', '', 'es');
insert into cues.cue_content values
(201, 29, '¿De verdad se puede conocer un país sin hablar su idioma?', '', 'es');
insert into cues.cue_content values
(202, 30, '¿Hace falta ganar mucho dinero para disfrutar de la vida?', '', 'es');
insert into cues.cue_content values
(203, 31, '¿Ha cambiado Internet el comportamiento en el trabajo?', '', 'es');
insert into cues.cue_content values
(204, 32, '¿Qué tipo de medio prefieres para informarte y por qué?', '', 'es');
insert into cues.cue_content values
(205, 33, 'Para vivir bien en un país extranjero, ¿es necesario relacionarse con la gente local?', '', 'es');
insert into cues.cue_content values
(206, 34, 'Al vivir en el extranjero, ¿los padres deberían hablar con sus hijos en el idioma del país o en su lengua materna?', '', 'es');
insert into cues.cue_content values
(207, 35, '¿Se puede desarrollar la economía y a la vez proteger el medio ambiente?', '', 'es');
insert into cues.cue_content values
(208, 36, 'En un país de acogida, ¿crees que hay que preservar las tradiciones y la cultura propias?', '', 'es');
insert into cues.cue_content values
(209, 37, '¿Dar dinero a los niños por buenas notas es una buena idea?', '', 'es');
insert into cues.cue_content values
(210, 38, '¿El bienestar en el trabajo es realmente importante?', '', 'es');
insert into cues.cue_content values
(211, 39, '¿Los deportistas profesionales se merecen sus sueldos tan altos?', '', 'es');
insert into cues.cue_content values
(212, 40, '¿La televisión está desapareciendo poco a poco?', '', 'es');
insert into cues.cue_content values
(213, 41, '¿Los niños pasan demasiado tiempo delante de las pantallas?', '', 'es');
insert into cues.cue_content values
(214, 42, '¿Es fácil encontrar trabajo en el extranjero?', '', 'es');
insert into cues.cue_content values
(215, 43, 'Al vivir en un país de acogida, ¿la gente debería cambiar sus hábitos?', '', 'es');