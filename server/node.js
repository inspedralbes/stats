const express = require('express');
const cors = require('cors');
const { exec } = require('child_process');
const fs = require('fs');  // Importar fs per gestionar els arxius
const app = express();
const port = 3000;

// Permet CORS per totes les orígens
app.use(cors());

app.get('/stats', (req, res) => {
    const repoUrl = req.query.repoUrl;

    // Validar que s'ha passat una URL del repositori
    if (!repoUrl) {
        console.log('Error: No s\'ha proporcionat cap URL del repositori.');
        res.status(400).send({ error: 'Es requereix una URL del repositori.' });
        return;
    }

    console.log(`Rebuda petició per obtenir estadístiques per al repositori: ${repoUrl}`);

    const localRepoPath = '/tmp/repo';  // O qualsevol directori temporal on es clonaran els repositoris

    // Comprovar si el directori existeix
    if (fs.existsSync(localRepoPath)) {
        console.log(`El directori ${localRepoPath} ja existeix. Realitzant un git pull per actualitzar-lo...`);
        exec(`cd ${localRepoPath} && git pull`, (err, stdout, stderr) => {
            if (err) {
                console.error('Error al fer git pull:', stderr);
                res.status(500).send({ error: stderr });
                return;
            }
            console.log('Repositori actualitzat correctament amb git pull.');
            getStats(localRepoPath);  // Obtenir les estadístiques després de fer git pull
        });
    } else {
        console.log('Clonant el repositori per primera vegada...');
        exec(`git clone ${repoUrl} ${localRepoPath}`, (err, stdout, stderr) => {
            if (err) {
                console.error('Error al clonar el repositori:', stderr);
                res.status(500).send({ error: stderr });
                return;
            }

            console.log('Repositori clonat correctament.');
            getStats(localRepoPath);  // Obtenir les estadístiques després de clonar
        });
    }

    function getStats(repoPath) {
        // Obtenir les estadístiques de les contribucions per autor en totes les branques
        console.log('Obtenint estadístiques de les contribucions a totes les branques...');

        exec(`cd ${repoPath} && git log --all --pretty='%an' | sort | uniq -c | sort -nr`, (err, stdout, stderr) => {
            if (err) {
                console.error('Error al obtenir les estadístiques de les contribucions:', stderr);
                res.status(500).send({ error: stderr });
                return;
            }

            // Processar les estadístiques de les contribucions
            const stats = stdout.split('\n').map(line => {
                const [lines, author] = line.trim().split(' ');
                return { author, lines: parseInt(lines) };
            });

            console.log('Estadístiques de les contribucions obtingudes correctament.');

            // Ara obtenim les estadístiques de les operacions de merge
            console.log('Obtenint estadístiques de les operacions de merge...');

            exec(`cd ${repoPath} && git log --all --merges --pretty='%an' | sort | uniq -c | sort -nr`, (err, stdout, stderr) => {
                if (err) {
                    console.error('Error al obtenir les estadístiques de les operacions de merge:', stderr);
                    res.status(500).send({ error: stderr });
                    return;
                }

                // Processar les estadístiques de *merge*
                const mergeStats = stdout.split('\n').map(line => {
                    const [merges, author] = line.trim().split(' ');
                    return { author, merges: parseInt(merges) };
                });

                console.log('Estadístiques de les operacions de merge obtingudes correctament.');

                // Combinar les estadístiques de contribucions i *merges*
                const combinedStats = stats.map(item => {
                    const merge = mergeStats.find(mergeItem => mergeItem.author === item.author);
                    return {
                        author: item.author,
                        lines: item.lines,
                        merges: merge ? merge.merges : 0  // Si no té merges, posar 0
                    };
                });

                console.log(`Enviant les estadístiques combinades:`, combinedStats);

                res.json(combinedStats);
            });
        });
    }
});

app.listen(port, () => {
    console.log(`Server running at http://localhost:${port}`);
});
