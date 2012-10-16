$(document).ready(function(){
    var upload_ready = false;
    var upload_data;
    var form_sent = false;

    ZeroClipboard.setMoviePath( '/js/ZeroClipboard.swf' );
    var clip = new ZeroClipboard.Client();
    clip.addEventListener( 'onComplete', my_complete );

    function my_complete( client, text ) {
        alert("Скопировано: \r\n" + text );
    }

    $('.file_input').change(function(){
       if(this.value)
       {
           $('form.upload').trigger('submit');
       }
    });

    $('form.upload').submit(function()
    {
        if (upload_ready)
        {
            return true;
        }

        $.ajax({
            url: '/register_upload',
            data: {filename: $('.file_input').val()},
            dataType: 'json',
            success: function(response)
            {
                $('.share').show();
                clip.setText(response.download_link);
                clip.glue( 'copy' );
                $('.share input').val(response.download_link);
                $('.share a').attr('href', response.download_link);
                upload_data = response;

                var interval = setInterval(function(){
                    $.ajax({
                        url: '/upload_status',
                        data: {transfer_id: upload_data.upload_id},
                        dataType: 'json',
                        success: function(r)
                        {
                            switch (r.status)
                            {
                                case "client.connected":
                                    if (!form_sent)
                                    {
//                                        $('.share').hide();
                                        $('.wait').show();
                                        upload_ready = true;
                                        $('form.upload')[0].action = "/upload/?transfer_id=" + r.upload_id;

                                        $('form.upload')[0].submit();
                                        form_sent = true;
                                    }
                                    break;
                                case 'uploading':
                                    $('.progress .bar').css('width', Math.ceil(100 * r.bytes_uploaded/ r.bytes_total) + '%');
                                    break;
                                case 'finished':
                                    $('.progress .bar').css('width', '100%');
                                    clearInterval(interval);

                                    upload_data = null;
                                    form_sent = false;
                                    upload_ready = false;
                                    break;
                            }
                        }
                    })
                }, 500)
            }
        });

        return false;
    })
})