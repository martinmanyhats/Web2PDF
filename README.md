# README

TODO

- include PDFs from website
- what to do with attached Word/Excel files
- pages linked from footer
- check https://www.deddingtonhistory.uk/buildings/windmillcentre

Code added to mysource_matrix/core/include/asset.inc:

        public function getAssetUrlsKeywordReplacement()
        {
                // retrieve all existing URLs for this asset
                $sql = 'SELECT l.url, l.http, l.https, u.urlid
                                FROM sq_ast_lookup l
                                        LEFT OUTER JOIN sq_ast_url u ON l.root_urlid = u.urlid
                                        LEFT OUTER JOIN sq_ast_path p ON l.assetid = p.assetid
                                WHERE l.assetid = :assetid';

                try {
                        $query = MatrixDAL::preparePdoQuery($sql);
                        MatrixDAL::bindValueToPdo($query, 'assetid', $this->id);
                        $urls = MatrixDAL::executePdoAssoc($query);
                } catch (Exception $e) {
                        throw new Exception('Unable to get fll urls for asset "'.$this->name.'" (#'.$this->id.') due to database error: '.$e->getMessage());
                }
                $urls = array_map(function($url) { return $url['url']; }, $urls);
                return json_encode($urls);
        }
