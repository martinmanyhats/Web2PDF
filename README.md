# README

TODO

~~- include PDFs from website~~
~~- what to do with attached Word/Excel files~~
- landscape for Excel files
~~- check https://www.deddingtonhistory.uk/buildings/windmillcentre~~
~~- encoding for asset names~~
- video assets
- PDF outline for PDFs
- review tmp/pdf_duplicates, tmp/ignored_links

Code added to mysource_matrix/core/include/asset.inc:

        /*
         * martin@martinreed.co.uk 2025-09-04
         * Return array: [0] array of webpaths, [1] redirection URL or ''
         */
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
                        throw new Exception('Unable to get all urls for asset "'.$this->name.'" (#'.$this->id.') due to database error: '.$e->getMessage());
                }
                $urls = array_map(function($url) { return $url['url']; }, $urls);
                if (method_exists($this, '_getRedirectURL')) {
                        $redirect_url = $this->_getRedirectURL();
                }
                else {
                        $redirect_url = '';

                }
                return json_encode([$urls, $redirect_url], JSON_UNESCAPED_SLASHES);
        }

INSTRUCTIONS

* Clear Squiz cache
* Restart Web2Pdf
* http://127.0.0.1:3000/websites/1/spider
* http://127.0.0.1:3000/websites/1/generate_archive
* http://127.0.0.1:3000/websites/1/zip_archive


**Wordpress Plugin for Squiz metadata**

wp-content/plugins/squiz/squiz.php

```
<?php
/**
 * Plugin Name: Squiz
 * Version: 2.4.0
 * Author: Martin Reed <martin@martinreed.co.uk>
 * Description: Rails-driven asset registry with classic WordPress UI support.
 */

if (!defined('ABSPATH')) exit;

class Squiz {

    public static function boot() {
        add_action('init', [__CLASS__, 'register_meta']);
        add_action('rest_api_init', [__CLASS__, 'register_routes']);
        add_action('add_meta_boxes', [__CLASS__, 'register_page_meta_box']);
        add_action('add_meta_boxes_attachment', [__CLASS__, 'register_attachment_meta_box']);
    }

    /**
     * -------------------------------------------------------
     * META STORAGE (SAFE + REST EXPOSED)
     * -------------------------------------------------------
     */
    public static function register_meta() {

        register_meta('post', 'assetid', [
            'object_subtype'   => 'page',
            'type'             => 'integer',
            'single'           => true,
            'show_in_rest'     => true,
            'sanitize_callback'=> [__CLASS__, 'sanitize_assetid'],
        ]);

        register_meta('post', 'assetid', [
            'object_subtype'   => 'attachment',
            'type'             => 'integer',
            'single'           => true,
            'show_in_rest'     => true,
            'sanitize_callback'=> [__CLASS__, 'sanitize_assetid'],
        ]);
    }

    public static function sanitize_assetid($value) {
        return is_numeric($value) ? (int) $value : null;
    }

    /**
     * -------------------------------------------------------
     * REST API (Rails writes only)
     * -------------------------------------------------------
     */
    public static function register_routes() {

        register_rest_route('squiz/v2', '/asset', [
            'methods'  => 'POST',
            'callback' => [__CLASS__, 'set_assetid'],
            'permission_callback' => [__CLASS__, 'can_edit'],
        ]);

        register_rest_route('squiz/v2', '/asset/(?P<assetid>\d+)', [
            'methods'  => 'GET',
            'callback' => [__CLASS__, 'lookup'],
            'permission_callback' => '__return_true'
        ]);
    }

    public static function can_edit() {
        return current_user_can('edit_posts');
    }

    public static function set_assetid($request) {

        $post_id = (int) $request['post_id'];
        $assetid = (int) $request['assetid'];

        if (!$post_id || !$assetid) {
            return new WP_REST_Response(['error' => 'invalid_request'], 400);
        }

        if (get_post_meta($post_id, 'assetid', true)) {
            return new WP_REST_Response(['error' => 'already_set'], 409);
        }

        update_post_meta($post_id, 'assetid', $assetid);

        return [
            'ok' => true,
            'post_id' => $post_id,
            'assetid' => $assetid
        ];
    }

    public static function lookup($request) {

        $assetid = (int) $request['assetid'];

        $query = new WP_Query([
            'post_type'      => ['page', 'attachment'],
            'meta_key'       => 'assetid',
            'meta_value'     => $assetid,
            'posts_per_page' => 1,
        ]);

        if (!$query->have_posts()) {
            return new WP_REST_Response(['found' => false], 404);
        }

        $post = $query->posts[0];

        return [
            'found'   => true,
            'id'      => $post->ID,
            'type'    => $post->post_type,
            'assetid' => (int) get_post_meta($post->ID, 'assetid', true),
            'link'    => get_permalink($post->ID),
        ];
    }

    /**
     * -------------------------------------------------------
     * CLASSIC ADMIN UI - PAGES
     * -------------------------------------------------------
     */
    public static function register_page_meta_box() {

        add_meta_box(
            'squiz_assetid_page',
            'Asset ID',
            [__CLASS__, 'render_meta_box'],
            'page',
            'side'
        );
    }

    /**
     * -------------------------------------------------------
     * CLASSIC ADMIN UI - MEDIA ATTACHMENTS
     * -------------------------------------------------------
     */
    public static function register_attachment_meta_box() {

        add_meta_box(
            'squiz_assetid_attachment',
            'Asset ID',
            [__CLASS__, 'render_meta_box'],
            'attachment',
            'side'
        );
    }

    /**
     * -------------------------------------------------------
     * RENDER FIELD (READ-ONLY)
     * -------------------------------------------------------
     */
    public static function render_meta_box($post) {

        $value = (int) get_post_meta($post->ID, 'assetid', true);

        echo '<label style="font-weight:600;">Asset ID</label>';
        echo '<input type="number" readonly style="width:100%;margin-top:5px;" value="' . esc_attr($value) . '">';

        echo '<p style="font-size:11px;color:#666;margin-top:6px;">
            Managed externally via Rails (write-once)
        </p>';
    }
}

/**
 * -------------------------------------------------------
 * BOOT STRAP (SAFE)
 * -------------------------------------------------------
 */
add_action('plugins_loaded', ['Squiz', 'boot']);
```